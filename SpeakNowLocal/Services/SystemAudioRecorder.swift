import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

@available(macOS 13.0, *)
class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var isCapturing = false
    private var outputURL: URL

    override init() {
        outputURL = Constants.tempSystemAudioURL
        super.init()
    }

    func startCapture() async throws {
        guard !isCapturing else { return }

        // Get shareable content (we need a display to attach to for audio-only capture)
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = availableContent.displays.first else {
            throw SystemAudioError.noDisplayFound
        }

        // Configure for audio-only capture
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16000
        config.channelCount = 1

        // Minimize video by setting tiny dimensions (audio-only, so video is unused)
        config.width = 2
        config.height = 2

        // Filter: capture the full display (all apps' audio)
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        // Prepare output WAV file
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        audioFile = outputFile

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.andycarlson.SpeakNowLocal.audioCapture"))
        try await stream.startCapture()

        self.stream = stream
        isCapturing = true
    }

    func stopCapture() async -> URL? {
        guard isCapturing else { return nil }
        isCapturing = false

        do {
            try await stream?.stopCapture()
        } catch {
            // Non-fatal: stream may have already stopped
        }

        stream = nil
        audioFile = nil

        // Return the URL only if the file has content
        let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attrs?[.size] as? Int ?? 0
        // WAV header is 44 bytes; if only header or empty, treat as empty
        guard fileSize > 44 else { return nil }

        return outputURL
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, isCapturing else { return }
        guard let audioFile = audioFile else { return }

        // Convert CMSampleBuffer to AVAudioPCMBuffer and write
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }

        guard let audioFormat = extractAudioFormat(from: sampleBuffer) else { return }
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        // Copy raw bytes from block buffer into PCM buffer
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let src = dataPointer else { return }

        if let dest = pcmBuffer.int16ChannelData {
            memcpy(dest[0], src, min(totalLength, Int(frameCount) * 2))
        } else if let destFloat = pcmBuffer.floatChannelData {
            // If the buffer uses float format, convert from int16
            let int16Ptr = src.withMemoryRebound(to: Int16.self, capacity: frameCount) { $0 }
            for i in 0..<frameCount {
                destFloat[0][i] = Float(int16Ptr[i]) / 32768.0
            }
        }

        try? audioFile.write(from: pcmBuffer)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isCapturing = false
        audioFile = nil
    }

    // MARK: - Helpers

    private func extractAudioFormat(from sampleBuffer: CMSampleBuffer) -> AVAudioFormat? {
        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        guard CMAudioFormatDescriptionGetStreamBasicDescription(desc) != nil else { return nil }

        // We always write at 16kHz mono int16 (matches our SCStreamConfiguration)
        return AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)
    }
}

enum SystemAudioError: LocalizedError {
    case noDisplayFound
    case captureNotStarted

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No display found for system audio capture."
        case .captureNotStarted:
            return "System audio capture was not started."
        }
    }
}
