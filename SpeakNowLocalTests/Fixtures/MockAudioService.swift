import Foundation
@testable import SpeakNowLocal

class MockAudioService: AudioService {
    // MARK: - SpeakNowService Protocol
    
    var id: String = "com.audio.recorder"
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
        isCleanedUp = true
    }
    
    // MARK: - AudioService Protocol
    
    var startRecordingError: Error?
    var startRecordingCallCount = 0
    var isRecording = false
    
    func startRecording() throws {
        startRecordingCallCount += 1
        if let error = startRecordingError {
            throw error
        }
        isRecording = true
    }
    
    var stopRecordingCallCount = 0
    
    func stopRecording() -> URL {
        stopRecordingCallCount += 1
        isRecording = false
        return URL(fileURLWithPath: "/tmp/mock-recording-\(UUID().uuidString).wav")
    }
    
    var mockDuration: TimeInterval = 0.0
    var recordingDuration: TimeInterval {
        mockDuration
    }
    
    var audioFormat: String {
        "16kHz mono 16-bit PCM WAV"
    }
    
    // MARK: - Call Tracking
    
    var allCalls: [String] = []
    
    func recordCall(_ name: String) {
        allCalls.append(name)
    }
}
