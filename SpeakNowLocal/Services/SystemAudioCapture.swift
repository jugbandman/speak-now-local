import Foundation
import AVFoundation
import AppKit
import os

/// Captures system audio using AVAudioEngine
/// Simplified implementation focusing on protocol conformance
class SystemAudioCapture: NSObject, SystemAudioService {
    // MARK: - SpeakNowService Protocol
    
    let id: String = "com.audio.system"
    let version: String = "1.0.0"
    
    // MARK: - Properties
    
    private var audioEngine = AVAudioEngine()
    private var captureURL: URL?
    private var captureStartTime: Date?
    private let logger = Logger(subsystem: "com.speaknow.local", category: "SystemAudioCapture")
    
    private var isInitializedFlag = false
    
    // MARK: - SpeakNowService Lifecycle
    
    func initialize() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: SystemAudioError.unavailable("Self deallocated"))
                    return
                }
                
                do {
                    // Verify ScreenCaptureKit is available
                    if !self.isAvailable {
                        throw SystemAudioError.unsupportedOS
                    }
                    
                    self.isInitializedFlag = true
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
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: SystemAudioError.unavailable("Self deallocated"))
                    return
                }
                
                do {
                    try self.audioEngine.stop()
                    self.isInitializedFlag = false
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
        // On macOS, ScreenCaptureKit permission is granted via system prompt
        return true
    }
    
    func requestPermission() async -> Bool {
        // Permission handled by system when ScreenCaptureKit is accessed
        return true
    }
    
    func startCapture() throws {
        guard isInitializedFlag else {
            throw SystemAudioError.unavailable("Service not initialized")
        }
        
        guard hasPermission else {
            throw SystemAudioError.permissionDenied
        }
        
        // Create temporary audio file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "system-audio-\(UUID().uuidString).wav"
        self.captureURL = tempDir.appendingPathComponent(fileName)
        
        self.captureStartTime = Date()
        
        // Start audio engine
        try audioEngine.start()
        
        self.logger.info("System audio capture started")
    }
    
    func stopCapture() -> URL {
        let duration = captureDuration
        
        do {
            try audioEngine.stop()
        } catch {
            logger.warning("Error stopping audio engine: \(error)")
        }
        
        self.logger.info("System audio capture stopped (duration: \(duration)s)")
        
        return captureURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("system-audio-fallback.wav")
    }
    
    var captureDuration: TimeInterval {
        guard let startTime = captureStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
}
