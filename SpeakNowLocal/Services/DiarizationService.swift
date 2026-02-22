import Foundation
import os

/// Performs speaker diarization using pyannote-audio
/// Identifies speakers in audio and labels transcript with speaker names
class PyAnnoteDiarizer: NSObject, DiarizationService {
    // MARK: - SpeakNowService Protocol
    
    let id: String = "com.diarization.pyannote"
    let version: String = "1.0.0"
    
    // MARK: - Properties
    
    private var isModelLoadedFlag = false
    private let logger = Logger(subsystem: "com.speaknow.local", category: "DiarizationService")
    private let pythonQueue = DispatchQueue(label: "com.speaknow.diarization.python")
    
    // Paths
    private let pythonExecutable: String
    private let modelCacheDir: URL
    private let diarizationScript: URL
    
    override init() {
        // Determine Python executable (user's system Python or bundled)
        self.pythonExecutable = Self.findPythonExecutable()
        
        // Model cache directory
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.modelCacheDir = appSupportDir.appendingPathComponent("com.speaknow.local/models/diarization")
        
        // Diarization script (bundled or temp)
        let tempDir = FileManager.default.temporaryDirectory
        self.diarizationScript = tempDir.appendingPathComponent("diarize_audio.py")
        
        super.init()
    }
    
    // MARK: - SpeakNowService Lifecycle
    
    func initialize() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            pythonQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: DiarizationError.modelNotLoaded)
                    return
                }
                
                do {
                    // Verify Python is available
                    try self.verifyPythonInstallation()
                    
                    // Create model cache directory
                    try FileManager.default.createDirectory(
                        at: self.modelCacheDir,
                        withIntermediateDirectories: true
                    )
                    
                    // Write diarization script if not present
                    try self.ensureDiarizationScript()
                    
                    self.logger.info("DiarizationService initialized successfully")
                    continuation.resume()
                } catch {
                    self.logger.error("DiarizationService initialization failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func cleanup() async throws {
        // Clean up temp files if needed
        do {
            if FileManager.default.fileExists(atPath: diarizationScript.path) {
                try FileManager.default.removeItem(at: diarizationScript)
            }
            logger.info("DiarizationService cleaned up")
        } catch {
            logger.warning("Error during cleanup: \(error)")
        }
    }
    
    // MARK: - DiarizationService Protocol
    
    var isModelLoaded: Bool {
        isModelLoadedFlag
    }
    
    func loadModel() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            pythonQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: DiarizationError.modelNotLoaded)
                    return
                }
                
                do {
                    // Run Python to download/cache pyannote model
                    let script = """
                    import os
                    os.environ['HF_HOME'] = '\(self.modelCacheDir.path)'
                    from pyannote.audio import Pipeline
                    pipeline = Pipeline.from_pretrained('pyannote/speaker-diarization-3.0')
                    print('Model loaded successfully')
                    """
                    
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: self.pythonExecutable)
                    process.arguments = ["-c", script]
                    
                    let pipe = Pipe()
                    let errorPipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = errorPipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        self.isModelLoadedFlag = true
                        self.logger.info("Pyannote model loaded successfully")
                        continuation.resume()
                    } else {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        throw DiarizationError.analysisFailedError(errorStr)
                    }
                } catch {
                    self.logger.error("Failed to load model: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func diarize(audioURL: URL) async throws -> [SpeakerSegment] {
        guard isModelLoaded else {
            throw DiarizationError.modelNotLoaded
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            pythonQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: DiarizationError.modelNotLoaded)
                    return
                }
                
                do {
                    // Validate audio file
                    guard FileManager.default.fileExists(atPath: audioURL.path) else {
                        throw DiarizationError.unsupportedAudioFormat("File not found: \(audioURL.path)")
                    }
                    
                    // Run diarization via Python subprocess
                    let segments = try self.runDiarization(audioURL: audioURL)
                    
                    self.logger.info("Diarization complete: \(segments.count) speaker segments")
                    continuation.resume(returning: segments)
                } catch {
                    self.logger.error("Diarization failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func labelTranscript(_ text: String, with segments: [SpeakerSegment]) -> String {
        // Split transcript into lines
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        
        // Simple line-based labeling (could be improved with word-level timing)
        var labeledLines: [String] = []
        var currentSpeaker: String?
        
        for line in lines {
            // Find speaker for this line based on timing
            // For now, simple heuristic: assign speaker based on line position
            let speakerLabel = determineSpeaker(for: line, from: segments)
            
            if speakerLabel != currentSpeaker && !speakerLabel.isEmpty {
                currentSpeaker = speakerLabel
                labeledLines.append("\n**\(speakerLabel):**")
            }
            
            labeledLines.append(line)
        }
        
        return labeledLines.joined(separator: "\n")
    }
    
    // MARK: - Private Helpers
    
    private func verifyPythonInstallation() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonExecutable)
        process.arguments = ["-c", "import pyannote.audio; print('OK')"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw DiarizationError.pythonNotAvailable
        }
    }
    
    private func ensureDiarizationScript() throws {
        if FileManager.default.fileExists(atPath: diarizationScript.path) {
            return
        }
        
        let script = """
        import sys
        import json
        from pathlib import Path
        
        # Usage: python diarize_audio.py <audio_path> <model_cache_dir>
        audio_path = sys.argv[1]
        model_cache = sys.argv[2] if len(sys.argv) > 2 else None
        
        if model_cache:
            import os
            os.environ['HF_HOME'] = model_cache
        
        from pyannote.audio import Pipeline
        
        # Load pipeline
        pipeline = Pipeline.from_pretrained('pyannote/speaker-diarization-3.0')
        
        # Run diarization
        diarization = pipeline(audio_path)
        
        # Output as JSON
        segments = []
        for turn, _, speaker in diarization.itertracks(yield_label=True):
            segments.append({
                'speaker': speaker,
                'start': float(turn.start),
                'end': float(turn.end)
            })
        
        print(json.dumps(segments))
        """
        
        try script.write(to: diarizationScript, atomically: true, encoding: .utf8)
    }
    
    private func runDiarization(audioURL: URL) throws -> [SpeakerSegment] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonExecutable)
        process.arguments = [
            diarizationScript.path,
            audioURL.path,
            modelCacheDir.path
        ]
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw DiarizationError.analysisFailedError(errorStr)
        }
        
        // Parse JSON output
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let jsonString = String(data: outputData, encoding: .utf8) else {
            throw DiarizationError.analysisFailedError("Invalid output format")
        }
        
        let decoder = JSONDecoder()
        let jsonData = jsonString.data(using: .utf8) ?? Data()
        
        struct SegmentJSON: Codable {
            let speaker: String
            let start: TimeInterval
            let end: TimeInterval
        }
        
        let jsonSegments = try decoder.decode([SegmentJSON].self, from: jsonData)
        
        let segments = jsonSegments.map { json in
            SpeakerSegment(
                speaker: json.speaker,
                startTime: json.start,
                endTime: json.end
            )
        }
        
        return segments
    }
    
    private func determineSpeaker(for line: String, from segments: [SpeakerSegment]) -> String {
        // Simple heuristic: use first segment if available
        // In a real implementation, would use word-level timing from transcript
        guard !segments.isEmpty else { return "" }
        
        // For now, return the speaker with the most segments
        let speakerCounts = segments.reduce(into: [String: Int]()) { counts, segment in
            counts[segment.speaker, default: 0] += 1
        }
        
        return speakerCounts.max(by: { $0.value < $1.value })?.key ?? ""
    }
    
    private static func findPythonExecutable() -> String {
        // Try common Python executable locations
        let candidates = [
            "/usr/local/bin/python3",
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
            "python3",
            "python"
        ]
        
        for candidate in candidates {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: candidate)
            process.arguments = ["--version"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    return candidate
                }
            } catch {
                continue
            }
        }
        
        // Fallback
        return "python3"
    }
}
