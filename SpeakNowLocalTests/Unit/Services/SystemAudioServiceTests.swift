import XCTest
@testable import SpeakNowLocal

class SystemAudioServiceTests: XCTestCase {
    var mockSystemAudio: MockSystemAudioService!
    
    override func setUp() {
        super.setUp()
        mockSystemAudio = MockSystemAudioService()
    }
    
    override func tearDown() {
        mockSystemAudio.reset()
        super.tearDown()
    }
    
    // MARK: - Protocol Conformance
    
    func testSystemAudioServiceConformsToProtocol() {
        let service: SystemAudioService = mockSystemAudio
        XCTAssertNotNil(service)
    }
    
    func testIdPropertyExists() {
        XCTAssertEqual(mockSystemAudio.id, "com.audio.system")
    }
    
    func testVersionPropertyExists() {
        XCTAssertEqual(mockSystemAudio.version, "1.0.0")
    }
    
    // MARK: - Initialization & Cleanup
    
    func testInitializeSucceeds() async throws {
        try await mockSystemAudio.initialize()
        XCTAssertTrue(mockSystemAudio.isInitialized)
    }
    
    func testInitializeThrowsError() async {
        mockSystemAudio.initializeError = SystemAudioError.unavailable("Test unavailable")
        
        do {
            try await mockSystemAudio.initialize()
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is SystemAudioError)
        }
    }
    
    func testCleanupSucceeds() async throws {
        try await mockSystemAudio.cleanup()
        XCTAssertTrue(mockSystemAudio.isCleanedUp)
    }
    
    func testCleanupStopsCapture() async throws {
        try mockSystemAudio.startCapture()
        try await mockSystemAudio.cleanup()
        XCTAssertFalse(mockSystemAudio.isCapturing)
    }
    
    // MARK: - Availability
    
    func testIsAvailableTrue() {
        mockSystemAudio.mockIsAvailable = true
        XCTAssertTrue(mockSystemAudio.isAvailable)
    }
    
    func testIsAvailableFalse() {
        mockSystemAudio.mockIsAvailable = false
        XCTAssertFalse(mockSystemAudio.isAvailable)
    }
    
    // MARK: - Permissions
    
    func testHasPermissionTrue() {
        mockSystemAudio.mockHasPermission = true
        XCTAssertTrue(mockSystemAudio.hasPermission)
    }
    
    func testHasPermissionFalse() {
        mockSystemAudio.mockHasPermission = false
        XCTAssertFalse(mockSystemAudio.hasPermission)
    }
    
    func testRequestPermissionGranted() async {
        mockSystemAudio.mockPermissionResult = true
        let granted = await mockSystemAudio.requestPermission()
        XCTAssertTrue(granted)
    }
    
    func testRequestPermissionDenied() async {
        mockSystemAudio.mockPermissionResult = false
        let granted = await mockSystemAudio.requestPermission()
        XCTAssertFalse(granted)
    }
    
    func testStartCaptureWithoutPermission() throws {
        mockSystemAudio.mockHasPermission = false
        // Mock should allow starting anyway for test purposes
        try mockSystemAudio.startCapture()
        XCTAssertTrue(mockSystemAudio.isCapturing)
    }
    
    // MARK: - Capture Lifecycle
    
    func testStartCaptureSucceeds() throws {
        try mockSystemAudio.startCapture()
        XCTAssertEqual(mockSystemAudio.startCaptureCallCount, 1)
        XCTAssertTrue(mockSystemAudio.isCapturing)
    }
    
    func testStartCaptureWhenAlreadyCapturing() throws {
        try mockSystemAudio.startCapture()
        
        do {
            try mockSystemAudio.startCapture()
            XCTFail("Should have thrown captureAlreadyActive")
        } catch let error as SystemAudioError {
            if case .captureAlreadyActive = error {
                // Expected
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
    
    func testStartCaptureThrowsError() throws {
        mockSystemAudio.startCaptureError = SystemAudioError.captureFailed("ScreenCaptureKit unavailable")
        
        do {
            try mockSystemAudio.startCapture()
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is SystemAudioError)
        }
    }
    
    func testStopCaptureReturnsURL() throws {
        try mockSystemAudio.startCapture()
        let url = mockSystemAudio.stopCapture()
        
        XCTAssertTrue(url.pathExtension == "wav")
        XCTAssertFalse(mockSystemAudio.isCapturing)
    }
    
    func testStopCaptureCallCount() throws {
        try mockSystemAudio.startCapture()
        _ = mockSystemAudio.stopCapture()
        XCTAssertEqual(mockSystemAudio.stopCaptureCallCount, 1)
    }
    
    // MARK: - Capture Duration
    
    func testCaptureDuration() throws {
        try mockSystemAudio.startCapture()
        mockSystemAudio.mockCaptureDuration = 5.0
        XCTAssertEqual(mockSystemAudio.captureDuration, 5.0)
    }
    
    // MARK: - Error Cases
    
    func testStartCaptureWhenUnavailable() throws {
        mockSystemAudio.mockIsAvailable = false
        mockSystemAudio.startCaptureError = SystemAudioError.unavailable("macOS 12.3")
        
        do {
            try mockSystemAudio.startCapture()
            XCTFail("Should have thrown unavailable error")
        } catch {
            XCTAssertTrue(error is SystemAudioError)
        }
    }
}
