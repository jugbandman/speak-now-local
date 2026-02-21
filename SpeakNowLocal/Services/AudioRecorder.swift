import AVFoundation

class AudioRecorder: AudioService {
    private var recorder: AVAudioRecorder?
    private var recordingStartTime: Date?

    // MARK: - SpeakNowService Protocol
    
    var id: String = "com.audio.recorder"
    var version: String = "1.0.0"
    
    func initialize() async throws {
        // No async initialization needed for AudioRecorder
    }
    
    func cleanup() async throws {
        // Stop recording if active
        stopRecording()
    }

    // MARK: - AudioService Protocol
    
    var currentRecordingURL: URL {
        Constants.tempRecordingURL
    }

    var recordingDuration: TimeInterval {
        guard let start = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
    
    var audioFormat: String {
        "16kHz mono 16-bit PCM WAV"
    }

    func startRecording() throws {
        let url = currentRecordingURL

        // 16kHz mono 16-bit PCM WAV (exactly what whisper-cpp expects)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.record()
        recordingStartTime = Date()
    }

    func stopRecording() -> URL {
        recorder?.stop()
        recorder = nil
        return currentRecordingURL
    }

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static var hasPermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}
