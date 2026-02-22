import AVFoundation
import CoreAudio

class AudioRecorder: AudioService {
    private var recorder: AVAudioRecorder?
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingStartTime: Date?

    // MARK: - SpeakNowService Protocol

    var id: String = "com.audio.recorder"
    var version: String = "1.0.0"

    func initialize() async throws {}

    func cleanup() async throws {
        _ = stopRecording()
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
        let deviceUID = UserDefaults.standard.string(forKey: Constants.keyInputDeviceUID) ?? ""
        if deviceUID.isEmpty {
            try startRecordingDefault()
        } else {
            try startRecordingWithDevice(uid: deviceUID)
        }
    }

    func stopRecording() -> URL {
        if let eng = engine {
            eng.inputNode.removeTap(onBus: 0)
            eng.stop()
            engine = nil
            audioFile = nil
        } else {
            recorder?.stop()
            recorder = nil
        }
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

    // MARK: - Private

    private func startRecordingDefault() throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        recorder = try AVAudioRecorder(url: currentRecordingURL, settings: settings)
        recorder?.record()
        recordingStartTime = Date()
    }

    private func startRecordingWithDevice(uid: String) throws {
        guard let deviceID = AudioDeviceManager.deviceID(forUID: uid) else {
            throw NSError(domain: "AudioRecorder", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Audio device not found: \(uid)"])
        }

        let eng = AVAudioEngine()

        // Point the engine's input at the selected device
        var devID = deviceID
        let result = AudioUnitSetProperty(
            eng.inputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard result == noErr else {
            throw NSError(domain: "AudioRecorder", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not set audio device (OSStatus \(result))"])
        }

        // Target: 16kHz mono Int16 PCM (whisper-compatible)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        let file = try AVAudioFile(
            forWriting: currentRecordingURL,
            settings: targetFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        audioFile = file

        let inputFormat = eng.inputNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "AudioRecorder", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not create audio format converter"])
        }

        eng.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let file = self.audioFile else { return }
            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames) else { return }
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if error == nil {
                try? file.write(from: converted)
            }
        }

        try eng.start()
        engine = eng
        recordingStartTime = Date()
    }
}
