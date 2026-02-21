import XCTest
@testable import SpeakNowLocal

class DiarizationServiceTests: XCTestCase {
    var mockDiarization: MockDiarizationService!
    
    override func setUp() {
        super.setUp()
        mockDiarization = MockDiarizationService()
    }
    
    override func tearDown() {
        mockDiarization.reset()
        super.tearDown()
    }
    
    // MARK: - Protocol Conformance
    
    func testDiarizationServiceConformsToProtocol() {
        let service: DiarizationService = mockDiarization
        XCTAssertNotNil(service)
    }
    
    func testIdPropertyExists() {
        XCTAssertEqual(mockDiarization.id, "com.diarization.pyannote")
    }
    
    func testVersionPropertyExists() {
        XCTAssertEqual(mockDiarization.version, "1.0.0")
    }
    
    // MARK: - Initialization & Cleanup
    
    func testInitializeSucceeds() async throws {
        try await mockDiarization.initialize()
        XCTAssertTrue(mockDiarization.isInitialized)
    }
    
    func testCleanupSucceeds() async throws {
        try await mockDiarization.cleanup()
        XCTAssertTrue(mockDiarization.isCleanedUp)
    }
    
    // MARK: - Model Loading
    
    func testLoadModelSucceeds() async throws {
        try await mockDiarization.loadModel()
        XCTAssertEqual(mockDiarization.loadModelCallCount, 1)
        XCTAssertTrue(mockDiarization.isModelLoaded)
    }
    
    func testLoadModelThrowsError() async {
        mockDiarization.loadModelError = DiarizationError.pythonNotAvailable
        
        do {
            try await mockDiarization.loadModel()
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is DiarizationError)
        }
    }
    
    func testIsModelLoadedFalse() {
        mockDiarization.mockIsModelLoaded = false
        XCTAssertFalse(mockDiarization.isModelLoaded)
    }
    
    func testDiarizeWithoutLoadingModel() async throws {
        mockDiarization.mockIsModelLoaded = false
        
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")
        let segments = try await mockDiarization.diarize(audioURL: audioURL)
        
        // Mock allows diarizing even without loaded model
        XCTAssertFalse(segments.isEmpty)
    }
    
    // MARK: - Diarization
    
    func testDiarizeReturnsSegments() async throws {
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")
        let segments = try await mockDiarization.diarize(audioURL: audioURL)
        
        XCTAssertEqual(mockDiarization.diarizeCallCount, 1)
        XCTAssertFalse(segments.isEmpty)
    }
    
    func testDiarizeMultipleSpeakers() async throws {
        mockDiarization.mockSegments = [
            SpeakerSegment(speaker: "Speaker 1", startTime: 0, endTime: 3),
            SpeakerSegment(speaker: "Speaker 2", startTime: 3, endTime: 6),
            SpeakerSegment(speaker: "Speaker 3", startTime: 6, endTime: 9)
        ]
        
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")
        let segments = try await mockDiarization.diarize(audioURL: audioURL)
        
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].speaker, "Speaker 1")
        XCTAssertEqual(segments[1].speaker, "Speaker 2")
        XCTAssertEqual(segments[2].speaker, "Speaker 3")
    }
    
    func testDiarizeEmptyResult() async throws {
        mockDiarization.mockSegments = []
        
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")
        let segments = try await mockDiarization.diarize(audioURL: audioURL)
        
        XCTAssertTrue(segments.isEmpty)
    }
    
    func testDiarizeThrowsError() async {
        mockDiarization.diarizeError = DiarizationError.audioTooShort
        
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")
        do {
            _ = try await mockDiarization.diarize(audioURL: audioURL)
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is DiarizationError)
        }
    }
    
    // MARK: - Speaker Segments
    
    func testSpeakerSegmentDuration() {
        let segment = SpeakerSegment(speaker: "Speaker 1", startTime: 0, endTime: 5)
        XCTAssertEqual(segment.duration, 5.0)
    }
    
    func testSpeakerSegmentDurationFractional() {
        let segment = SpeakerSegment(speaker: "Speaker 1", startTime: 1.5, endTime: 4.2)
        XCTAssertEqual(segment.duration, 2.7, accuracy: 0.001)
    }
    
    // MARK: - Label Transcript
    
    func testLabelTranscriptWithSegments() {
        let transcript = "Hello there\nHow are you\nI am good"
        let segments = [
            SpeakerSegment(speaker: "Alice", startTime: 0, endTime: 2),
            SpeakerSegment(speaker: "Bob", startTime: 2, endTime: 4)
        ]
        
        let labeled = mockDiarization.labelTranscript(transcript, with: segments)
        
        XCTAssertTrue(labeled.contains("Alice:"))
        XCTAssertTrue(labeled.contains("Bob:"))
    }
    
    func testLabelTranscriptSingleSpeaker() {
        let transcript = "Line 1\nLine 2\nLine 3"
        let segments = [
            SpeakerSegment(speaker: "Speaker 1", startTime: 0, endTime: 10)
        ]
        
        let labeled = mockDiarization.labelTranscript(transcript, with: segments)
        
        let lines = labeled.components(separatedBy: "\n")
        for line in lines where !line.isEmpty {
            XCTAssertTrue(line.contains("Speaker 1:"))
        }
    }
    
    func testLabelTranscriptEmpty() {
        let transcript = ""
        let segments: [SpeakerSegment] = []
        
        let labeled = mockDiarization.labelTranscript(transcript, with: segments)
        
        XCTAssertTrue(labeled.isEmpty)
    }
}
