import Foundation
@testable import SpeakNowLocal

class MockStorageService: StorageService {
    // MARK: - SpeakNowService Protocol
    
    var id: String = "com.storage.transcript"
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
    
    // MARK: - StorageService Protocol
    
    private var inMemoryStore: [TranscriptEntry] = []
    
    var saveError: Error?
    var saveCallCount = 0
    
    func save(_ entry: TranscriptEntry) throws {
        saveCallCount += 1
        if let error = saveError {
            throw error
        }
        inMemoryStore.append(entry)
    }
    
    func load(limit: Int) -> [TranscriptEntry] {
        // Return most recent first
        return Array(inMemoryStore.suffix(limit).reversed())
    }
    
    var clearError: Error?
    var clearCallCount = 0
    
    func clear() throws {
        clearCallCount += 1
        if let error = clearError {
            throw error
        }
        inMemoryStore.removeAll()
    }
    
    // MARK: - Test Utilities
    
    func allEntries() -> [TranscriptEntry] {
        return inMemoryStore
    }
    
    func reset() {
        inMemoryStore.removeAll()
        saveCallCount = 0
        clearCallCount = 0
        saveError = nil
        clearError = nil
    }
}
