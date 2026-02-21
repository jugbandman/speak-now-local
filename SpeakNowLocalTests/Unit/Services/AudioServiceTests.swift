import XCTest
@testable import SpeakNowLocal

class AudioServiceTests: XCTestCase {
    var mockAudio: MockAudioService!
    
    override func setUp() {
        super.setUp()
        mockAudio = MockAudioService()
    }
    
    // MARK: - Protocol Conformance
    
    func testAudioServiceConformsToProtocol() {
        let service: AudioService = mockAudio
        XCTAssertNotNil(service)
    }
    
    func testIdPropertyExists() {
        XCTAssertEqual(mockAudio.id, "com.audio.recorder")
    }
    
    func testVersionPropertyExists() {
        XCTAssertEqual(mockAudio.version, "1.0.0")
    }
    
    // MARK: - Initialization & Cleanup
    
    func testInitializeSucceeds() async throws {
        try await mockAudio.initialize()
        XCTAssertTrue(mockAudio.isInitialized)
    }
    
    func testInitializeThrowsError() async {
        mockAudio.initializeError = PluginError.initializationFailed("Test error")
        
        do {
            try await mockAudio.initialize()
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is PluginError)
        }
    }
    
    func testCleanupSucceeds() async throws {
        try await mockAudio.cleanup()
        XCTAssertTrue(mockAudio.isCleanedUp)
    }
    
    // MARK: - Recording Control
    
    func testStartRecordingSucceeds() throws {
        try mockAudio.startRecording()
        XCTAssertEqual(mockAudio.startRecordingCallCount, 1)
        XCTAssertTrue(mockAudio.isRecording)
    }
    
    func testStartRecordingThrowsError() throws {
        mockAudio.startRecordingError = PluginError.permissionDenied("Microphone")
        
        do {
            try mockAudio.startRecording()
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is PluginError)
        }
    }
    
    func testStopRecordingReturnsURL() throws {
        try mockAudio.startRecording()
        let url = mockAudio.stopRecording()
        
        XCTAssertTrue(url.pathExtension == "wav")
        XCTAssertFalse(mockAudio.isRecording)
    }
    
    // MARK: - Recording Duration
    
    func testRecordingDurationIncreases() throws {
        try mockAudio.startRecording()
        
        let initialDuration = mockAudio.recordingDuration
        mockAudio.mockDuration = 5.0
        
        XCTAssertEqual(mockAudio.recordingDuration, 5.0)
    }
    
    func testAudioFormatIsCorrect() {
        XCTAssertEqual(mockAudio.audioFormat, "16kHz mono 16-bit PCM WAV")
    }
}
