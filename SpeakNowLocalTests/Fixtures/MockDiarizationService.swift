import Foundation
@testable import SpeakNowLocal

class MockDiarizationService: DiarizationService {
    // MARK: - SpeakNowService Protocol
    
    var id: String = "com.diarization.pyannote"
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
    
    // MARK: - DiarizationService Protocol
    
    var loadModelError: Error?
    var loadModelCallCount = 0
    var mockIsModelLoaded = false
    
    func loadModel() async throws {
        loadModelCallCount += 1
        if let error = loadModelError {
            throw error
        }
        mockIsModelLoaded = true
    }
    
    var isModelLoaded: Bool {
        mockIsModelLoaded
    }
    
    var diarizeError: Error?
    var diarizeCallCount = 0
    var mockSegments: [SpeakerSegment] = [
        SpeakerSegment(speaker: "Speaker 1", startTime: 0.0, endTime: 5.0),
        SpeakerSegment(speaker: "Speaker 2", startTime: 5.0, endTime: 10.0),
        SpeakerSegment(speaker: "Speaker 1", startTime: 10.0, endTime: 15.0)
    ]
    
    func diarize(audioURL: URL) async throws -> [SpeakerSegment] {
        diarizeCallCount += 1
        if let error = diarizeError {
            throw error
        }
        return mockSegments
    }
    
    func labelTranscript(_ text: String, with segments: [SpeakerSegment]) -> String {
        var result = ""
        let lines = text.components(separatedBy: "\n")
        var segmentIndex = 0
        var currentTime: TimeInterval = 0.0
        let timePerLine = segments.last?.endTime ?? 10.0 / TimeInterval(lines.count)
        
        for line in lines {
            // Find which speaker this line belongs to
            while segmentIndex < segments.count && currentTime > segments[segmentIndex].endTime {
                segmentIndex += 1
            }
            
            if segmentIndex < segments.count {
                let speaker = segments[segmentIndex].speaker
                result += "\(speaker): \(line)\n"
            } else {
                result += line + "\n"
            }
            
            currentTime += timePerLine
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Test Utilities
    
    func reset() {
        loadModelCallCount = 0
        diarizeCallCount = 0
        mockIsModelLoaded = false
        loadModelError = nil
        diarizeError = nil
        initializeError = nil
        cleanupError = nil
    }
}
