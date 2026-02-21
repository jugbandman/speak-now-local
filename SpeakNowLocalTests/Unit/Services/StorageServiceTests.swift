import XCTest
@testable import SpeakNowLocal

class StorageServiceTests: XCTestCase {
    var mockStorage: MockStorageService!
    
    override func setUp() {
        super.setUp()
        mockStorage = MockStorageService()
    }
    
    // MARK: - Protocol Conformance
    
    func testStorageServiceConformsToProtocol() {
        let service: StorageService = mockStorage
        XCTAssertNotNil(service)
    }
    
    func testIdPropertyExists() {
        XCTAssertEqual(mockStorage.id, "com.storage.transcript")
    }
    
    func testVersionPropertyExists() {
        XCTAssertEqual(mockStorage.version, "1.0.0")
    }
    
    // MARK: - Initialization & Cleanup
    
    func testInitializeSucceeds() async throws {
        try await mockStorage.initialize()
        XCTAssertTrue(mockStorage.isInitialized)
    }
    
    func testCleanupSucceeds() async throws {
        try await mockStorage.cleanup()
        XCTAssertTrue(mockStorage.isCleanedUp)
    }
    
    // MARK: - Save & Load
    
    func testSaveTranscriptSucceeds() throws {
        let entry = TranscriptEntry(
            date: Date(),
            text: "Test transcript",
            model: "base.en",
            duration: 10.5
        )
        
        try mockStorage.save(entry)
        XCTAssertEqual(mockStorage.saveCallCount, 1)
    }
    
    func testSaveThrowsError() throws {
        mockStorage.saveError = PluginError.permissionDenied("Write failed")
        
        let entry = TranscriptEntry(
            date: Date(),
            text: "Test transcript",
            model: "base.en",
            duration: 10.5
        )
        
        do {
            try mockStorage.save(entry)
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is PluginError)
        }
    }
    
    func testLoadTranscriptsReturnsArray() throws {
        let entry1 = TranscriptEntry(date: Date(), text: "First", model: "base", duration: 5)
        let entry2 = TranscriptEntry(date: Date(), text: "Second", model: "base", duration: 8)
        
        try mockStorage.save(entry1)
        try mockStorage.save(entry2)
        
        let loaded = mockStorage.load(limit: 10)
        XCTAssertEqual(loaded.count, 2)
    }
    
    func testLoadTranscriptsMostRecentFirst() throws {
        let now = Date()
        let pastDate = now.addingTimeInterval(-3600)
        
        let oldEntry = TranscriptEntry(date: pastDate, text: "Old", model: "base", duration: 5)
        let newEntry = TranscriptEntry(date: now, text: "New", model: "base", duration: 8)
        
        try mockStorage.save(oldEntry)
        try mockStorage.save(newEntry)
        
        let loaded = mockStorage.load(limit: 10)
        XCTAssertEqual(loaded.first?.text, "New")
        XCTAssertEqual(loaded.last?.text, "Old")
    }
    
    func testLoadRespectLimit() throws {
        for i in 0..<10 {
            let entry = TranscriptEntry(
                date: Date().addingTimeInterval(TimeInterval(i)),
                text: "Transcript \(i)",
                model: "base",
                duration: 5
            )
            try mockStorage.save(entry)
        }
        
        let loaded = mockStorage.load(limit: 5)
        XCTAssertEqual(loaded.count, 5)
    }
    
    // MARK: - Clear
    
    func testClearRemovesAllTranscripts() throws {
        let entry = TranscriptEntry(date: Date(), text: "Test", model: "base", duration: 5)
        try mockStorage.save(entry)
        
        XCTAssertEqual(mockStorage.load(limit: 100).count, 1)
        
        try mockStorage.clear()
        XCTAssertEqual(mockStorage.load(limit: 100).count, 0)
    }
    
    func testClearThrowsError() throws {
        mockStorage.clearError = PluginError.permissionDenied("Cannot delete")
        
        do {
            try mockStorage.clear()
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is PluginError)
        }
    }
}
