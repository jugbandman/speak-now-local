import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import os

/// Captures system audio via ScreenCaptureKit (macOS 13.0+)
/// Writes 16kHz mono Float32 PCM WAV suitable for whisper-cpp.
///
/// SCStream delivers audio at the system's native rate (often 48 kHz, stereo),
/// so each incoming buffer is converted to 16 kHz mono Float32 via AVAudioConverter
/// before being written to the destination file. All file/converter access happens
/// on a single private serial queue (the same one used as the sample-handler queue)
/// to avoid data races.
@available(macOS 13.0, *)
class SystemAudioCapture: NSObject, SystemAudioService, SCStreamOutput {
    // MARK: - SpeakNowService Protocol

    let id: String = "com.audio.system"
    let version: String = "1.0.0"

    // MARK: - Properties

    private var stream: SCStream?

    /// Serial queue that owns all access to `audioFile` and `converter`.
    /// This is also the sample-handler queue passed to addStreamOutput, so the
    /// SCStreamOutput callback runs here too — no locking needed.
    private let audioQueue = DispatchQueue(label: "com.speaknow.local.systemaudio")

    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    private var captureURL: URL?
    private var captureStartTime: Date?
    private var isInitializedFlag = false
    private var isCapturing = false
    private let logger = Logger(subsystem: "com.speaknow.local", category: "SystemAudioCapture")

    /// Target output format: 16 kHz mono Float32 (non-interleaved) for whisper-cpp.
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    // MARK: - SpeakNowService Lifecycle

    func initialize() async throws {
        if !isAvailable {
            throw SystemAudioError.unsupportedOS
        }

        // Preflight ScreenCaptureKit by fetching shareable content
        _ = try await SCShareableContent.current
        isInitializedFlag = true
        logger.info("SystemAudioCapture initialized with ScreenCaptureKit")
    }

    func cleanup() async throws {
        if isCapturing {
            try? await stream?.stopCapture()
            stream = nil
            isCapturing = false
            audioQueue.sync {
                self.audioFile = nil
                self.converter = nil
                self.sourceFormat = nil
            }
        }
        isInitializedFlag = false
        logger.info("SystemAudioCapture cleaned up")
    }

    // MARK: - SystemAudioService Protocol

    var isAvailable: Bool {
        return true // class is already gated by @available(macOS 13.0, *)
    }

    var hasPermission: Bool {
        return CGPreflightScreenCaptureAccess()
    }

    func requestPermission() async -> Bool {
        return CGRequestScreenCaptureAccess()
    }

    func startCapture() async throws {
        guard isInitializedFlag else {
            throw SystemAudioError.unavailable("Service not initialized")
        }
        guard hasPermission else {
            throw SystemAudioError.permissionDenied
        }
        guard !isCapturing else {
            throw SystemAudioError.captureAlreadyActive
        }

        // Get shareable content and build an audio-only filter
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw SystemAudioError.unavailable("No display found for content filter")
        }

        let filter = SCContentFilter(
            display: display,
            excludingWindows: []
        )

        // Configure for audio capture. We request 16 kHz mono, but SCStream may
        // still deliver buffers at the system's native rate, so we always convert.
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 16000
        config.channelCount = 1
        // P2: never record the app's own sound effects.
        config.excludesCurrentProcessAudio = true

        // Prepare output WAV file (16 kHz mono Float32)
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "system-audio-\(UUID().uuidString).wav"
        let fileURL = tempDir.appendingPathComponent(fileName)
        self.captureURL = fileURL

        do {
            let file = try AVAudioFile(
                forWriting: fileURL,
                settings: targetFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            audioQueue.sync {
                self.audioFile = file
                self.converter = nil
                self.sourceFormat = nil
            }
        } catch {
            throw SystemAudioError.encodingFailed("Could not create audio file: \(error.localizedDescription)")
        }

        // Create and start the stream. The sample handler runs on audioQueue,
        // the same queue that owns audioFile/converter.
        let scStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        self.stream = scStream

        self.captureStartTime = Date()
        try await scStream.startCapture()
        self.isCapturing = true

        logger.info("System audio capture started via ScreenCaptureKit")
    }

    func stopCapture() async -> URL? {
        let duration = captureDuration

        // Stop the stream first; this flushes any buffered samples to the
        // sample handler (which runs on audioQueue) before returning.
        try? await stream?.stopCapture()
        stream = nil
        isCapturing = false

        // Flush/close the file on the serial queue so any in-flight write
        // completes before we nil it out and return the URL.
        let url: URL? = audioQueue.sync {
            self.audioFile = nil
            self.converter = nil
            self.sourceFormat = nil
            return self.captureURL
        }

        logger.info("System audio capture stopped (duration: \(duration)s)")
        return url
    }

    var captureDuration: TimeInterval {
        guard let startTime = captureStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    // MARK: - SCStreamOutput (runs on audioQueue — serial, no locking needed)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else { return }
        guard sampleBuffer.isValid else { return }
        guard let audioFile = self.audioFile else { return }

        guard let formatDesc = sampleBuffer.formatDescription,
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return
        }
        var asbd = asbdPtr.pointee

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }

        // Build an AVAudioFormat describing the actual incoming buffer.
        guard let inputFormat = AVAudioFormat(streamDescription: &asbd) else {
            return
        }

        // Build the input PCM buffer from the CMSampleBuffer.
        guard let inputBuffer = makeInputBuffer(
            from: sampleBuffer,
            format: inputFormat,
            frameCount: AVAudioFrameCount(frameCount)
        ) else {
            return
        }

        // Lazily create the converter once we know the real source format.
        if converter == nil || sourceFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
            sourceFormat = inputFormat
        }
        guard let converter = converter else { return }

        // Allocate an output buffer sized for the resampled frame count, with a
        // little headroom for rounding.
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 1024
        guard outCapacity > 0,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            return
        }

        // Feed the source buffer exactly once, then signal end of stream.
        var fedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if fedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            fedInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let conversionError = conversionError {
            logger.warning("Audio conversion failed: \(conversionError.localizedDescription)")
            return
        }
        guard status != .error, outputBuffer.frameLength > 0 else { return }

        do {
            try audioFile.write(from: outputBuffer)
        } catch {
            logger.warning("Failed to write audio buffer: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Copies the raw audio data from a CMSampleBuffer into an AVAudioPCMBuffer
    /// matching the supplied (source) format.
    private func makeInputBuffer(
        from sampleBuffer: CMSampleBuffer,
        format: AVAudioFormat,
        frameCount: AVAudioFrameCount
    ) -> AVAudioPCMBuffer? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        pcmBuffer.frameLength = frameCount

        var dataLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &dataLength,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let srcData = dataPointer else { return nil }

        let asbd = format.streamDescription.pointee
        let isInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0

        // SCStream typically delivers Float32. Handle float buffers; bail on
        // anything unexpected so we never write garbage.
        guard isFloat else { return nil }

        if isInterleaved {
            // Single contiguous block: copy straight into channel 0's storage.
            guard let dst = pcmBuffer.floatChannelData?[0] else { return nil }
            let byteCount = min(dataLength, Int(frameCount) * Int(asbd.mChannelsPerFrame) * MemoryLayout<Float>.size)
            memcpy(dst, srcData, byteCount)
        } else {
            // Non-interleaved: the block buffer holds each channel's samples back
            // to back. Copy per channel.
            guard let channels = pcmBuffer.floatChannelData else { return nil }
            let channelCount = Int(asbd.mChannelsPerFrame)
            let bytesPerChannel = Int(frameCount) * MemoryLayout<Float>.size
            for ch in 0..<channelCount {
                let offset = ch * bytesPerChannel
                guard offset + bytesPerChannel <= dataLength else { break }
                memcpy(channels[ch], srcData.advanced(by: offset), bytesPerChannel)
            }
        }

        return pcmBuffer
    }
}
