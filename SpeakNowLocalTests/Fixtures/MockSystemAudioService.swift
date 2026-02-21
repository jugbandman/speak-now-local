import Foundation
@testable import SpeakNowLocal

class MockSystemAudioService: SystemAudioService {
    // MARK: - SpeakNowService Protocol
    
    var id: String = "com.audio.system"
    var version: String = "1.0.0"
    
    var initializeError: Error?
    var isInitialized = false
    
    var cleanupError: Error?
    var isCleanedUp = false
    
    func initialize() async throws {
        if let error = initializeError {
            throw error
        }
        isInitialized = true
    }
    
    func cleanup() async throws {
        if let error = cleanupError {
            throw error
        }
        if isCapturing {
            _ = stopCapture()
        }
        isCleanedUp = true
    }
    
    // MARK: - SystemAudioService Protocol
    
    var mockIsAvailable = true
    var isAvailable: Bool {
        mockIsAvailable
    }
    
    var mockHasPermission = true
    var hasPermission: Bool {
        mockHasPermission
    }
    
    var mockPermissionResult = true
    func requestPermission() async -> Bool {
        mockPermissionResult
    }
    
    var startCaptureError: Error?
    var startCaptureCallCount = 0
    var isCapturing = false
    
    func startCapture() throws {
        startCaptureCallCount += 1
        if let error = startCaptureError {
            throw error
        }
        if isCapturing {
            throw SystemAudioError.captureAlreadyActive
        }
        isCapturing = true
    }
    
    var stopCaptureCallCount = 0
    var mockCaptureURL: URL = URL(fileURLWithPath: "/tmp/system-audio-\(UUID().uuidString).wav")
    
    func stopCapture() -> URL {
        stopCaptureCallCount += 1
        isCapturing = false
        return mockCaptureURL
    }
    
    var mockCaptureDuration: TimeInterval = 0.0
    var captureDuration: TimeInterval {
        mockCaptureDuration
    }
    
    // MARK: - Test Utilities
    
    func reset() {
        startCaptureCallCount = 0
        stopCaptureCallCount = 0
        isCapturing = false
        isInitialized = false
        isCleanedUp = false
        startCaptureError = nil
        cleanupError = nil
        initializeError = nil
    }
}
