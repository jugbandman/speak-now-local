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

    private func runWhisper(executablePath: String, modelPath: String, filePath: String) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [
            "--model", modelPath,
            "--file", filePath,
            "--no-timestamps",
            "--no-prints",
            "--threads", "\(Constants.defaultThreads)",
            "--language", "en"
        ]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

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
