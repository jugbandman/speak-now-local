import AppKit
import os

/// Keeps a whisper model loaded between takes by running whisper.cpp's own
/// `whisper-server` next to `whisper-cli`. A take then skips the model load
/// that whisper-cli repeats every time.
///
/// Best effort by design. If the server binary is missing, still loading, or
/// fails in any way, the caller falls back to whisper-cli for that take. The
/// server stops after 15 idle minutes and when the app quits.
final class WhisperServer {
    static let shared = WhisperServer()

    let port = 8178
    static let idleStop: TimeInterval = 15 * 60

    private let lock = NSLock()
    private var process: Process?
    private var loadedModelPath: String?
    private var idleWork: DispatchWorkItem?
    private let logger = Logger(subsystem: "com.speaknow.local", category: "WhisperServer")

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.stop() }
    }

    static func serverPath(forCLI cliPath: String) -> String {
        (cliPath as NSString).deletingLastPathComponent + "/whisper-server"
    }

    /// Start the server for this model if it is not already running it.
    func warmUp(cliPath: String, modelPath: String) {
        let serverPath = Self.serverPath(forCLI: cliPath)
        guard FileManager.default.isExecutableFile(atPath: serverPath),
              FileManager.default.fileExists(atPath: modelPath) else { return }

        lock.lock()
        defer { lock.unlock() }
        if let running = process, running.isRunning, loadedModelPath == modelPath {
            scheduleIdleStopLocked()
            return
        }
        stopLocked()
        killStaleServer()

        let language = modelPath.hasSuffix(".en.bin") ? "en" : "auto"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: serverPath)
        p.arguments = [
            "--model", modelPath,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--threads", "\(Constants.defaultThreads)",
            "--language", language
        ]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            process = p
            loadedModelPath = modelPath
            logger.info("whisper-server starting for \(modelPath)")
            scheduleIdleStopLocked()
        } catch {
            logger.warning("whisper-server failed to start: \(error.localizedDescription)")
        }
    }

    /// Whether a take for this model can try the server.
    func isRunning(for modelPath: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning == true && loadedModelPath == modelPath
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
    }

    /// Transcribe through the running server. Throws if it is not reachable yet
    /// (still loading the model) or returns nothing, so the caller falls back.
    func transcribe(fileURL: URL, prompt: String) async throws -> String {
        touchIdle()

        let boundary = "speaknow-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("response_format", "json")
        field("temperature", "0.0")
        if !prompt.isEmpty { field("prompt", prompt) }
        let audio = try Data(contentsOf: fileURL)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"take.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/inference")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw WhisperTranscriber.TranscriptionError.processError("whisper-server returned an error")
        }
        let text: String
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let t = obj["text"] as? String {
            text = t
        } else {
            text = String(data: data, encoding: .utf8) ?? ""
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw WhisperTranscriber.TranscriptionError.emptyOutput }
        return cleaned
    }

    private func touchIdle() {
        lock.lock()
        defer { lock.unlock() }
        scheduleIdleStopLocked()
    }

    /// A server left over from a crash or an Xcode stop holds the port, so the
    /// new one could not bind. Clear it before starting.
    private func killStaleServer() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", "whisper-server.*--port \(port)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    // MARK: - Private, call with the lock held

    private func stopLocked() {
        idleWork?.cancel()
        idleWork = nil
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        loadedModelPath = nil
    }

    private func scheduleIdleStopLocked() {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleStop, execute: work)
    }
}
