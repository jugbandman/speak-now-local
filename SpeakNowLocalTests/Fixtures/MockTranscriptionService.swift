import Foundation
@testable import SpeakNowLocal

class MockTranscriptionService: TranscriptionService {
    // MARK: - SpeakNowService Protocol
    
    var id: String = "com.transcription.whisper"
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
    
    // MARK: - TranscriptionService Protocol
    
    var transcribeError: Error?
    var transcribeCallCount = 0
    var mockTranscriptText = "This is a mock transcription of the audio file."
    
    func transcribe(audioURL: URL, modelName: String) async throws -> String {
        transcribeCallCount += 1
        if let error = transcribeError {
            throw error
        }
        return mockTranscriptText
    }
    
    func availableModels() -> [WhisperModel] {
        WhisperModel.allCases
    }
    
    var loadModelError: Error?
    var loadModelCallCount = 0
    var activeModel: String?
    
    func loadModel(_ name: String) async throws {
        loadModelCallCount += 1
        if let error = loadModelError {
            throw error
        }
        activeModel = name
    }
    
    // MARK: - Call Tracking

    var recordedCalls: [String] = []

    // MARK: - Test Utilities

    func reset() {
        transcribeCallCount = 0
        loadModelCallCount = 0
        activeModel = nil
        transcribeError = nil
        loadModelError = nil
        initializeError = nil
        cleanupError = nil
        isInitialized = false
        isCleanedUp = false
        recordedCalls.removeAll()
    }
}
