import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import os

@available(macOS 13.0, *)
class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let logger = Logger(subsystem: "com.speaknow.local", category: "ScreenRecorder")
    // Serial queue keeps sessionStarted flag race-free between video and audio callbacks
    private let outputQueue = DispatchQueue(label: "com.speaknow.local.screenrecorder", qos: .userInteractive)

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private(set) var captureURL: URL?
    private var captureStartTime: Date?
    private(set) var isCapturing = false

    var captureDuration: TimeInterval {
        guard let start = captureStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Window discovery

    static func availableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.windows
            .filter { !($0.title?.isEmpty ?? true) }
            .sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }
    }

    // MARK: - Capture lifecycle

    func startCapture(window: SCWindow? = nil) async throws -> URL {
        guard !isCapturing else { throw ScreenRecorderError.alreadyRecording }

        // Prepare output file
        let dir = URL(fileURLWithPath: Constants.defaultRecordingsDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let fileURL = dir.appendingPathComponent("screen-\(formatter.string(from: Date())).mov")
        captureURL = fileURL

        // Build content filter
        let filter: SCContentFilter
        if let window = window {
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { throw ScreenRecorderError.noDisplay }
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        let (width, height) = captureDimensions(for: window)

        // Stream config: video + system audio
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = width
        streamConfig.height = height
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        streamConfig.capturesAudio = true
        streamConfig.sampleRate = 44100
        streamConfig.channelCount = 2
        streamConfig.showsCursor = true

        // Asset writer
        let writer = try AVAssetWriter(url: fileURL, fileType: .mov)

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 5_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ]
        ])
        vInput.expectsMediaDataInRealTime = true
        writer.add(vInput)

        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: UInt32(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ])
        aInput.expectsMediaDataInRealTime = true
        writer.add(aInput)

        assetWriter = writer
        videoInput = vInput
        audioInput = aInput
        sessionStarted = false

        // Start stream
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

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        if let writer = assetWriter, writer.status == .writing {
            await writer.finishWriting()
        }

        assetWriter = nil
        videoInput = nil
        audioInput = nil
        sessionStarted = false

        logger.info("Screen recording finished: \(self.captureURL?.lastPathComponent ?? "?")")
        return self.captureURL
    }

    // MARK: - SCStreamOutput (runs on outputQueue — no locking needed for sessionStarted)

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
            if videoInput?.isReadyForMoreMediaData == true {
                videoInput?.append(sampleBuffer)
            }
        case .audio:
            if audioInput?.isReadyForMoreMediaData == true {
                audioInput?.append(sampleBuffer)
            }
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("SCStream stopped with error: \(error.localizedDescription)")
    }

    // MARK: - Helpers

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
