import Foundation

/// A single timestamped chunk of transcript output from whisper.
struct TranscriptSegment {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

class WhisperTranscriber: TranscriptionService {
    enum TranscriptionError: LocalizedError {
        case whisperNotFound(String)
        case modelNotFound(String)
        case processError(String)
        case emptyOutput

        var errorDescription: String? {
            switch self {
            case .whisperNotFound(let path):
                return "whisper-cli not found at \(path)"
            case .modelNotFound(let path):
                return "Model file not found at \(path)"
            case .processError(let message):
                return "Transcription failed: \(message)"
            case .emptyOutput:
                return "Transcription produced no output"
            }
        }
    }

    // MARK: - SpeakNowService Protocol
    
    var id: String = "com.transcription.whisper"
    var version: String = "1.0.0"
    
    func initialize() async throws {
        // Verify whisper is installed
        let whisperPath = UserDefaults.standard.string(forKey: Constants.keyWhisperPath)
            ?? Constants.defaultWhisperPath
        guard FileManager.default.fileExists(atPath: whisperPath) else {
            throw TranscriptionError.whisperNotFound(whisperPath)
        }
    }
    
    func cleanup() async throws {
        // No cleanup needed
    }
    
    // MARK: - TranscriptionService Protocol
    
    var activeModel: String? {
        UserDefaults.standard.string(forKey: Constants.keySelectedModel)
    }
    
    func availableModels() -> [WhisperModel] {
        WhisperModel.allCases
    }
    
    func loadModel(_ name: String) async throws {
        let modelPath = "\(Constants.whisperModelsDirectory)/ggml-\(name).bin"
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TranscriptionError.modelNotFound(modelPath)
        }
        UserDefaults.standard.set(name, forKey: Constants.keySelectedModel)
    }
    
    func transcribe(audioURL: URL, modelName: String) async throws -> String {
        let whisperPath = UserDefaults.standard.string(forKey: Constants.keyWhisperPath)
            ?? Constants.defaultWhisperPath
        let modelPath = "\(Constants.whisperModelsDirectory)/ggml-\(modelName).bin"

        guard FileManager.default.fileExists(atPath: whisperPath) else {
            throw TranscriptionError.whisperNotFound(whisperPath)
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TranscriptionError.modelNotFound(modelPath)
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.runWhisper(
                        executablePath: whisperPath,
                        modelPath: modelPath,
                        filePath: audioURL.path
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // Backward compat: old method name
    func transcribe(file: URL) async throws -> String {
        let modelName = UserDefaults.standard.string(forKey: Constants.keySelectedModel)
            ?? Constants.defaultModel
        return try await transcribe(audioURL: file, modelName: modelName)
    }

    /// Transcribe WITH timestamps and return parsed segments for diarization alignment.
    /// Uses the same whisper binary but keeps timestamps (no `--no-timestamps`).
    func transcribeSegments(audioURL: URL, modelName: String) async throws -> [TranscriptSegment] {
        let whisperPath = UserDefaults.standard.string(forKey: Constants.keyWhisperPath)
            ?? Constants.defaultWhisperPath
        let modelPath = "\(Constants.whisperModelsDirectory)/ggml-\(modelName).bin"

        guard FileManager.default.fileExists(atPath: whisperPath) else {
            throw TranscriptionError.whisperNotFound(whisperPath)
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TranscriptionError.modelNotFound(modelPath)
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let raw = try self.runWhisper(
                        executablePath: whisperPath,
                        modelPath: modelPath,
                        filePath: audioURL.path,
                        withTimestamps: true
                    )
                    let segments = self.parseTimestampedOutput(raw)
                    if segments.isEmpty {
                        throw TranscriptionError.emptyOutput
                    }
                    continuation.resume(returning: segments)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runWhisper(
        executablePath: String,
        modelPath: String,
        filePath: String,
        withTimestamps: Bool = false
    ) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        var arguments = [
            "--model", modelPath,
            "--file", filePath,
            "--no-prints",
            "--threads", "\(Constants.defaultThreads)",
            "--language", "en"
        ]
        if !withTimestamps {
            arguments.append("--no-timestamps")
        }
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Drain both pipes concurrently with the process running, so neither
        // stdout nor stderr can fill its 64 KB OS buffer and deadlock the child.
        var outputData = Data()
        var errorData = Data()
        let drainGroup = DispatchGroup()
        let drainQueue = DispatchQueue(label: "com.speaknow.local.whisper.drain", attributes: .concurrent)

        drainGroup.enter()
        drainQueue.async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            drainGroup.leave()
        }
        drainGroup.enter()
        drainQueue.async {
            errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            drainGroup.leave()
        }

        try process.run()
        process.waitUntilExit()
        // Both reads return EOF once the process closes its ends; wait for them.
        drainGroup.wait()

        if process.terminationStatus != 0 {
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.processError(errorOutput)
        }

        guard let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty else {
            throw TranscriptionError.emptyOutput
        }

        return output
    }

    /// Parse whisper timestamped output lines of the form:
    /// `[HH:MM:SS.mmm --> HH:MM:SS.mmm]   text`
    private func parseTimestampedOutput(_ output: String) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }
            guard let closeIdx = trimmed.firstIndex(of: "]") else { continue }

            // Bracket contents: "HH:MM:SS.mmm --> HH:MM:SS.mmm"
            let bracket = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeIdx])
            let parts = bracket.components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTimestamp(parts[0].trimmingCharacters(in: .whitespaces)),
                  let end = parseTimestamp(parts[1].trimmingCharacters(in: .whitespaces)) else {
                continue
            }

            let textStart = trimmed.index(after: closeIdx)
            let text = String(trimmed[textStart...]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            segments.append(TranscriptSegment(start: start, end: end, text: text))
        }

        return segments
    }

    /// Parse a timestamp "HH:MM:SS.mmm" (or "MM:SS.mmm") into seconds.
    private func parseTimestamp(_ s: String) -> TimeInterval? {
        let comps = s.components(separatedBy: ":")
        guard !comps.isEmpty else { return nil }

        var seconds: TimeInterval = 0
        for comp in comps {
            guard let value = TimeInterval(comp) else { return nil }
            seconds = seconds * 60 + value
        }
        return seconds
    }
}
