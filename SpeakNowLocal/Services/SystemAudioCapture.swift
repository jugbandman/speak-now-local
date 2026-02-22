import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import os

/// Captures system audio via ScreenCaptureKit (macOS 13.0+)
/// Writes 16kHz mono Float32 PCM WAV suitable for whisper-cpp
@available(macOS 13.0, *)
class SystemAudioCapture: NSObject, SystemAudioService, SCStreamOutput {
    // MARK: - SpeakNowService Protocol

    let id: String = "com.audio.system"
    let version: String = "1.0.0"

    // MARK: - Properties

    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var captureURL: URL?
    private var captureStartTime: Date?
    private var isInitializedFlag = false
    private var isCapturing = false
    private let logger = Logger(subsystem: "com.speaknow.local", category: "SystemAudioCapture")

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
            audioFile = nil
            isCapturing = false
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

        // Configure for 16kHz mono audio (no video)
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 16000
        config.channelCount = 1
        config.excludesCurrentProcessAudio = false

        // Prepare output WAV file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "system-audio-\(UUID().uuidString).wav"
        let fileURL = tempDir.appendingPathComponent(fileName)
        self.captureURL = fileURL

        guard let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw SystemAudioError.encodingFailed("Could not create AVAudioFormat")
        }

        do {
            self.audioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: audioFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw SystemAudioError.encodingFailed("Could not create audio file: \(error.localizedDescription)")
        }

        // Create and start the stream
        let scStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
        self.stream = scStream

        self.captureStartTime = Date()
        try await scStream.startCapture()
        self.isCapturing = true

        logger.info("System audio capture started via ScreenCaptureKit")
    }

    func stopCapture() -> URL {
        let duration = captureDuration

        if let stream = stream {
            // Fire-and-forget the async stop; stream will flush
            Task {
                try? await stream.stopCapture()
            }
        }

        stream = nil
        audioFile = nil
        isCapturing = false

        logger.info("System audio capture stopped (duration: \(duration)s)")

        return captureURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("system-audio-fallback.wav")
    }

    var captureDuration: TimeInterval {
        guard let startTime = captureStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else { return }
        guard sampleBuffer.isValid else { return }

        guard let formatDesc = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return
        }

        // Convert CMSampleBuffer to AVAudioPCMBuffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }

        guard let audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: asbd.pointee.mSampleRate,
            channels: AVAudioChannelCount(asbd.pointee.mChannelsPerFrame)
        ) else {
            return
        }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        var dataLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &dataLength, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let srcData = dataPointer else { return }

        if let channelData = pcmBuffer.floatChannelData {
            memcpy(channelData[0], srcData, min(dataLength, Int(frameCount) * MemoryLayout<Float>.size))
        }

        // Write to file
        do {
            try audioFile?.write(from: pcmBuffer)
        } catch {
            logger.warning("Failed to write audio buffer: \(error.localizedDescription)")
        }
    }
}
