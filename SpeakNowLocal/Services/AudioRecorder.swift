import AVFoundation

class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var recordingStartTime: Date?

    var currentRecordingURL: URL {
        Constants.tempRecordingURL
    }

    var recordingDuration: TimeInterval {
        guard let start = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(start)
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

    func stopRecording() {
        recorder?.stop()
        recorder = nil
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
