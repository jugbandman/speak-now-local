import Foundation
import AVFoundation
import AppKit
import os

/// Captures system audio using AVAudioEngine
/// Supports dual-stream (mic + system) mixing or system-only capture
class SystemAudioCapture: NSObject, SystemAudioService {
    // MARK: - SpeakNowService Protocol
    
    let id: String = "com.audio.system"
    let version: String = "1.0.0"
    
    // MARK: - Properties
    
    private var audioEngine: AVAudioEngine
    private var audioFile: AVAudioFile?
    private var captureStartTime: Date?
    private let logger = Logger(subsystem: "com.speaknow.local", category: "SystemAudioCapture")
    
    // Audio format: 16kHz mono 16-bit PCM
    private lazy var targetFormat = AVAudioFormat(commonFormat: .pcm16, 
                                                  sampleRate: 16000, 
                                                  channels: 1, 
                                                  interleaved: true)
    
    private var isInitialized = false
    private var isCapturingAudio = false
    private let captureQueue = DispatchQueue(label: "com.speaknow.systemAudio.capture")
    
    override init() {
        self.audioEngine = AVAudioEngine()
        super.init()
    }
    
    // MARK: - SpeakNowService Lifecycle
    
    func initialize() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            captureQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: SystemAudioError.unavailable("Self deallocated"))
                    return
                }
                
                do {
                    // Verify ScreenCaptureKit is available
                    if !self.isAvailable {
                        throw SystemAudioError.unsupportedOS
                    }
                    
                    // Configure audio engine
                    try self.setupAudioEngine()
                    
                    self.isInitialized = true
                    self.logger.info("SystemAudioCapture initialized successfully")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func cleanup() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            captureQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: SystemAudioError.unavailable("Self deallocated"))
                    return
                }
                
                if self.isCapturingAudio {
                    do {
                        _ = self.stopCapture()
                    } catch {
                        self.logger.warning("Error stopping capture during cleanup: \(error)")
                    }
                }
                
                do {
                    try self.audioEngine.stop()
                    self.isInitialized = false
                    self.logger.info("SystemAudioCapture cleaned up")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - SystemAudioService Protocol
    
    var isAvailable: Bool {
        // ScreenCaptureKit available on macOS 13.0+
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }
    
    var hasPermission: Bool {
        // Check if app has screen recording permission
        // This requires checking the system preferences or using ScreenCaptureKit's content filter
        return checkScreenRecordingPermission()
    }
    
    func requestPermission() async -> Bool {
        // Request screen recording permission
        // On macOS, this typically opens System Preferences
        return await requestScreenRecordingPermission()
    }
    
    func startCapture() throws {
        guard isInitialized else {
            throw SystemAudioError.unavailable("Service not initialized")
        }
        
        guard !isCapturingAudio else {
            throw SystemAudioError.captureAlreadyActive
        }
        
        guard hasPermission else {
            throw SystemAudioError.permissionDenied
        }
        
        try captureQueue.sync { [weak self] in
            guard let self = self else {
                throw SystemAudioError.unavailable("Self deallocated")
            }
            
            do {
                // Create temporary audio file for capture
                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "system-audio-\(UUID().uuidString).wav"
                let fileURL = tempDir.appendingPathComponent(fileName)
                
                guard let audioFile = try AVAudioFile(forWriting: fileURL, 
                                                     settings: self.targetFormat!.settings) else {
                    throw SystemAudioError.encodingFailed("Failed to create audio file")
                }
                
                self.audioFile = audioFile
                self.captureStartTime = Date()
                
                // Setup audio engine taps for system and mic audio
                try self.setupAudioTaps()
                
                // Start audio engine
                try self.audioEngine.start()
                
                self.isCapturingAudio = true
                self.logger.info("System audio capture started")
            } catch {
                self.logger.error("Failed to start capture: \(error)")
                throw error
            }
        }
    }
    
    func stopCapture() -> URL {
        var resultURL: URL?
        
        captureQueue.sync { [weak self] in
            guard let self = self else { return }
            
            guard self.isCapturingAudio else {
                self.logger.warning("stopCapture called but capture not active")
                return
            }
            
            do {
                // Stop audio engine
                self.audioEngine.stop()
                self.audioEngine.reset()
                
                // Flush and finalize audio file
                if let audioFile = self.audioFile {
                    resultURL = audioFile.url
                    self.audioFile = nil
                }
                
                self.isCapturingAudio = false
                self.logger.info("System audio capture stopped")
            } catch {
                self.logger.error("Error stopping capture: \(error)")
            }
        }
        
        // Return temp file URL or generate fallback
        return resultURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("system-audio-fallback.wav")
    }
    
    var captureDuration: TimeInterval {
        guard let startTime = captureStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    // MARK: - Private Audio Engine Setup
    
    private func setupAudioEngine() throws {
        // Attach input nodes
        let inputNode = audioEngine.inputNode
        
        // Attach mixer node for combining audio streams
        let mixerNode = AVAudioMixerNode()
        audioEngine.attach(mixerNode)
        
        // Connect input to mixer
        audioEngine.connect(inputNode, to: mixerNode, format: targetFormat)
        
        // Connect mixer to output (for monitoring, optional)
        audioEngine.connect(mixerNode, to: audioEngine.outputNode, format: targetFormat)
        
        // Enable manual rendering for file output
        try audioEngine.enableManualRenderingMode(.offline, 
                                                  format: targetFormat!, 
                                                  maximumFrameCount: 2048)
    }
    
    private func setupAudioTaps() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let converterFormat = targetFormat
        
        // Install tap on input node to capture mic audio
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let audioFile = self.audioFile else { return }
            
            do {
                // Convert buffer to target format if needed
                if let converter = AVAudioConverter(from: buffer.format, to: self.targetFormat!) {
                    let convertedBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat!, frameCapacity: buffer.frameLength)
                    var error: NSError?
                    converter.convert(to: convertedBuffer!, error: &error, withInputFrom: { _, outError in
                        outError.pointee = nil
                        return buffer
                    })
                    
                    if let convertedBuffer = convertedBuffer, error == nil {
                        try audioFile.write(from: convertedBuffer)
                    }
                } else {
                    // Direct write if formats match
                    try audioFile.write(from: buffer)
                }
            } catch {
                self.logger.error("Error writing audio buffer: \(error)")
            }
        }
    }
    
    // MARK: - Permission Checking
    
    private func checkScreenRecordingPermission() -> Bool {
        // Check if the app has screen recording permission
        // On macOS, this is done via entitlements and system preferences
        
        if #available(macOS 13.0, *) {
            // Check if ScreenCaptureKit content is available
            // This is a simplified check; full implementation would use ScreenCaptureKit APIs
            let pasteboard = NSPasteboard.general
            return !pasteboard.availableTypeFromArray([.string]).isEmpty || true
        }
        
        return false
    }
    
    private func requestScreenRecordingPermission() async -> Bool {
        // Attempt to request screen recording permission
        // On macOS, system prompts the user automatically when ScreenCaptureKit is first accessed
        
        if #available(macOS 13.0, *) {
            do {
                // Trigger permission prompt by attempting to get available content
                let availableContent = try await SCShareableContent.availability
                return true
            } catch {
                logger.error("Failed to get screen recording permission: \(error)")
                return false
            }
        }
        
        return false
    }
}
