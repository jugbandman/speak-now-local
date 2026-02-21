import XCTest
@testable import SpeakNowLocal

class TranscriptionServiceTests: XCTestCase {
    var mockTranscription: MockTranscriptionService!
    
    override func setUp() {
        super.setUp()
        mockTranscription = MockTranscriptionService()
    }
    
    // MARK: - Protocol Conformance
    
    func testTranscriptionServiceConformsToProtocol() {
        let service: TranscriptionService = mockTranscription
        XCTAssertNotNil(service)
    }
    
    func testIdPropertyExists() {
        XCTAssertEqual(mockTranscription.id, "com.transcription.whisper")
    }
    
    func testVersionPropertyExists() {
        XCTAssertEqual(mockTranscription.version, "1.0.0")
    }
    
    // MARK: - Initialization & Cleanup
    
    func testInitializeSucceeds() async throws {
        try await mockTranscription.initialize()
        XCTAssertTrue(mockTranscription.isInitialized)
    }
    
    func testCleanupSucceeds() async throws {
        try await mockTranscription.cleanup()
        XCTAssertTrue(mockTranscription.isCleanedUp)
    }
    
    // MARK: - Transcription
    
    func testTranscribeSucceeds() async throws {
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")
        let result = try await mockTranscription.transcribe(audioURL: audioURL, modelName: "base.en")
        
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(mockTranscription.transcribeCallCount, 1)
    }
    
    func testTranscribeThrowsError() async {
        mockTranscription.transcribeError = PluginError.loadFailed("Model not found")
        
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")
        do {
            _ = try await mockTranscription.transcribe(audioURL: audioURL, modelName: "base.en")
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is PluginError)
        }
    }
    
    // MARK: - Models
    
    func testAvailableModelsReturnsArray() {
        let models = mockTranscription.availableModels()
        
        XCTAssertFalse(models.isEmpty)
        XCTAssertTrue(models.count >= 4) // tiny, base, small, medium
    }
    
    func testLoadModelSucceeds() async throws {
        try await mockTranscription.loadModel("base.en")
        XCTAssertEqual(mockTranscription.loadModelCallCount, 1)
        XCTAssertEqual(mockTranscription.activeModel, "base.en")
    }
    
    func testLoadModelThrowsError() async {
        mockTranscription.loadModelError = PluginError.loadFailed("Download failed")
        
        do {
            try await mockTranscription.loadModel("large")
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is PluginError)
        }
    }
    
    func testActiveModelTracking() async throws {
        XCTAssertNil(mockTranscription.activeModel)
        
        try await mockTranscription.loadModel("tiny.en")
        XCTAssertEqual(mockTranscription.activeModel, "tiny.en")
        
        try await mockTranscription.loadModel("base.en")
        XCTAssertEqual(mockTranscription.activeModel, "base.en")
    }
}
