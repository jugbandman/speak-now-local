import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import os

@available(macOS 13.0, *)
class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let logger = Logger(subsystem: "com.speaknow.local", category: "ScreenRecorder")
    private let outputQueue = DispatchQueue(label: "com.speaknow.local.screenrecorder", qos: .userInteractive)

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var videoAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private(set) var captureURL: URL?
    private var captureStartTime: Date?
    private(set) var isCapturing = false

    // Called when macOS system UI stops the stream (e.g. user clicks "Stop sharing")
    var onUnexpectedStop: (() -> Void)?

    var captureDuration: TimeInterval {
        guard let start = captureStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Window discovery

    static func availableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.windows
            .filter { window in
                guard let title = window.title, !title.isEmpty else { return false }
                guard window.frame.width >= 200 && window.frame.height >= 100 else { return false }
                let bundleID = window.owningApplication?.bundleIdentifier ?? ""
                let skip = ["com.apple.dock", "com.apple.notificationcenterui",
                            "com.apple.controlcenter", "com.apple.systemuiserver"]
                return !skip.contains(bundleID)
            }
            .sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }
    }

    // MARK: - Capture lifecycle

    func startCapture(window: SCWindow? = nil) async throws -> URL {
        guard !isCapturing else { throw ScreenRecorderError.alreadyRecording }

        let dir = URL(fileURLWithPath: Constants.defaultRecordingsDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let fileURL = dir.appendingPathComponent("screen-\(formatter.string(from: Date())).mov")
        captureURL = fileURL

        let filter: SCContentFilter
        if let window = window {
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { throw ScreenRecorderError.noDisplay }
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        let (width, height) = captureDimensions(for: window)

        let streamConfig = SCStreamConfiguration()
        streamConfig.width = width
        streamConfig.height = height
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        streamConfig.capturesAudio = true
        streamConfig.sampleRate = 44100
        streamConfig.channelCount = 2
        streamConfig.excludesCurrentProcessAudio = false
        streamConfig.showsCursor = true
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA

        let writer = try AVAssetWriter(url: fileURL, fileType: .mov)

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ]
        ])
        vInput.expectsMediaDataInRealTime = true

        // Use pixel buffer adaptor — required for SCStream pixel buffers to encode correctly
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        writer.add(vInput)

        var channelLayout = AudioChannelLayout()
        channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        channelLayout.mChannelBitmap = AudioChannelBitmap(rawValue: 0)
        channelLayout.mNumberChannelDescriptions = 0
        let channelLayoutData = Data(bytes: &channelLayout, count: MemoryLayout<AudioChannelLayout>.size)

        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: UInt32(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
            AVChannelLayoutKey: channelLayoutData
        ])
        aInput.expectsMediaDataInRealTime = true
        writer.add(aInput)

        assetWriter = writer
        videoInput = vInput
        videoAdaptor = adaptor
        audioInput = aInput
        sessionStarted = false

        let scStream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
        stream = scStream

        captureStartTime = Date()
        try await scStream.startCapture()
        isCapturing = true
        logger.info("Screen recording started: \(fileURL.lastPathComponent)")
        return fileURL
    }

    func stopCapture() async -> URL? {
        guard isCapturing else { return captureURL }
        isCapturing = false
        captureStartTime = nil

        try? await stream?.stopCapture()
        stream = nil

        await finalizeWriter()
        return captureURL
    }

    // MARK: - SCStreamOutput (serial outputQueue — no locking needed)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid, let writer = assetWriter else { return }

        if !sessionStarted {
            guard writer.status == .unknown else { return }
            writer.startWriting()
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            sessionStarted = true
        }

        guard writer.status == .writing else { return }

        switch outputType {
        case .screen:
            guard let adaptor = videoAdaptor,
                  adaptor.assetWriterInput.isReadyForMoreMediaData,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            adaptor.append(pixelBuffer, withPresentationTime: sampleBuffer.presentationTimeStamp)

        case .audio:
            if audioInput?.isReadyForMoreMediaData == true {
                audioInput?.append(sampleBuffer)
            }

        default:
            break
        }
    }

    // User clicked "Stop sharing" in the macOS system UI
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.warning("SCStream stopped externally: \(error.localizedDescription)")
        guard isCapturing else { return }
        isCapturing = false
        captureStartTime = nil
        self.stream = nil

        Task {
            await finalizeWriter()
            onUnexpectedStop?()
        }
    }

    // MARK: - Helpers

    private func finalizeWriter() async {
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        if let writer = assetWriter, writer.status == .writing {
            await writer.finishWriting()
            logger.info("Screen recording finalized: \(self.captureURL?.lastPathComponent ?? "?")")
        }

        assetWriter = nil
        videoInput = nil
        videoAdaptor = nil
        audioInput = nil
        sessionStarted = false
    }

    private func captureDimensions(for window: SCWindow?) -> (Int, Int) {
        if let window = window {
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            return (max(2, Int(window.frame.width * scale)), max(2, Int(window.frame.height * scale)))
        }
        guard let screen = NSScreen.main else { return (1920, 1080) }
        let scale = screen.backingScaleFactor
        return (Int(screen.frame.width * scale), Int(screen.frame.height * scale))
    }
}

enum ScreenRecorderError: LocalizedError {
    case alreadyRecording
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .alreadyRecording: return "A screen recording is already in progress"
        case .noDisplay: return "No display found for screen capture"
        }
    }
}
