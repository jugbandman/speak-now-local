import Foundation

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

        // Pass 1 of the correction layer: the right spellings go in as a hint.
        let corrections = Corrections.load()
        let hint = Corrections.hint(corrections)

        var raw: String?
        // Warm path: the model is already loaded in whisper-server. Any
        // failure (still loading, not installed) falls through to whisper-cli.
        if ConfigStore.shared.bool(Constants.keyWarmEngine),
           WhisperServer.shared.isRunning(for: modelPath) {
            raw = try? await WhisperServer.shared.transcribe(fileURL: audioURL, prompt: hint)
        }
        if raw == nil {
            let cliText: String = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let result = try self.runWhisper(
                            executablePath: whisperPath,
                            modelPath: modelPath,
                            filePath: audioURL.path,
                            prompt: hint
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            raw = cliText
        }
        // Start or keep the server warm for the next take.
        if ConfigStore.shared.bool(Constants.keyWarmEngine) {
            WhisperServer.shared.warmUp(cliPath: whisperPath, modelPath: modelPath)
        }

        // Pass 2: whole-word replace of anything still misheard.
        let fixed = Corrections.apply(corrections, to: raw ?? "")
        Corrections.record(fixed.hits)
        return fixed.text
    }

    /// Load the model ahead of a take so the next stop is fast. Safe to call often.
    func warmUp(modelName: String) {
        guard ConfigStore.shared.bool(Constants.keyWarmEngine) else { return }
        let whisperPath = UserDefaults.standard.string(forKey: Constants.keyWhisperPath)
            ?? Constants.defaultWhisperPath
        let modelPath = "\(Constants.whisperModelsDirectory)/ggml-\(modelName).bin"
        WhisperServer.shared.warmUp(cliPath: whisperPath, modelPath: modelPath)
    }

    // Backward compat: old method name
    func transcribe(file: URL) async throws -> String {
        let modelName = UserDefaults.standard.string(forKey: Constants.keySelectedModel)
            ?? Constants.defaultModel
        return try await transcribe(audioURL: file, modelName: modelName)
    }

    private func runWhisper(
        executablePath: String,
        modelPath: String,
        filePath: String,
        prompt: String = ""
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
            // English-only models need "en". Multilingual models detect the language.
            "--language", modelPath.hasSuffix(".en.bin") ? "en" : "auto",
            "--no-timestamps"
        ]
        if !prompt.isEmpty {
            arguments += ["--prompt", prompt]
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
}
