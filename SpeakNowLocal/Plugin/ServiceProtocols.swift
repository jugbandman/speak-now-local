import Foundation

// MARK: - Base Service Protocol

/// All plugins conform to this base protocol
protocol SpeakNowService {
    /// Unique identifier for the service
    var id: String { get }
    
    /// Semantic version string (e.g., "1.0.0")
    var version: String { get }
    
    /// Called when service is loaded and about to be used
    func initialize() async throws
    
    /// Called when service is being unloaded
    func cleanup() async throws
}

// MARK: - Audio Service Protocol

protocol AudioService: SpeakNowService {
    /// Prepare audio system and begin recording
    func startRecording() throws
    
    /// Stop recording and return URL to WAV file
    func stopRecording() -> URL
    
    /// Current recording duration in seconds
    var recordingDuration: TimeInterval { get }
    
    /// Required: 16kHz mono 16-bit PCM WAV
    var audioFormat: String { get }
}

// MARK: - Transcription Service Protocol

protocol TranscriptionService: SpeakNowService {
    /// Transcribe audio file using specified model
    func transcribe(audioURL: URL, modelName: String) async throws -> String
    
    /// List available transcription models
    func availableModels() -> [WhisperModel]
    
    /// Load a model (may download if not cached)
    func loadModel(_ name: String) async throws
    
    /// Model currently active
    var activeModel: String? { get }
}

// MARK: - Output Service Protocol (Formatter)

protocol OutputService: SpeakNowService {
    /// Format transcript with metadata
    func format(transcript: String, context: TranscriptContext) -> String
    
    /// Execution priority (0 = lowest, plugins run in order)
    var priority: Int { get }
    
    /// User-facing name for this formatter
    var formatName: String { get }
}

// MARK: - Destination Service Protocol

protocol DestinationService: SpeakNowService {
    /// Send formatted text to external destination
    func send(text: String, context: TranscriptContext) async throws
    
    /// User-facing name (e.g., "File", "Slack", "Email")
    var destinationName: String { get }
    
    /// Whether this destination supports async operations
    var supportsAsync: Bool { get }
}

// MARK: - Storage Service Protocol

protocol StorageService: SpeakNowService {
    /// Persist a transcript entry
    func save(_ entry: TranscriptEntry) throws
    
    /// Load historical transcripts (most recent first)
    func load(limit: Int) -> [TranscriptEntry]
    
    /// Clear all transcripts
    func clear() throws
}

// MARK: - System Audio Service Protocol

protocol SystemAudioService: SpeakNowService {
    /// ScreenCaptureKit available on this macOS version
    var isAvailable: Bool { get }
    
    /// User has granted screen recording permission
    var hasPermission: Bool { get }
    
    /// Request screen recording permission
    func requestPermission() async -> Bool
    
    /// Start capturing system audio
    func startCapture() async throws
    
    /// Stop capturing and return URL to WAV file
    func stopCapture() -> URL
    
    /// Current capture duration in seconds
    var captureDuration: TimeInterval { get }
}

// MARK: - Diarization Service Protocol

protocol DiarizationService: SpeakNowService {
    /// Load diarization model (may download if not cached)
    func loadModel() async throws
    
    /// Whether model is loaded and ready
    var isModelLoaded: Bool { get }
    
    /// Analyze audio and identify speakers
    func diarize(audioURL: URL) async throws -> [SpeakerSegment]
    
    /// Add speaker labels to transcript text
    func labelTranscript(_ text: String, with segments: [SpeakerSegment]) -> String
}

// MARK: - LLM Service Protocol

protocol LLMService: SpeakNowService {
    /// Summarize text using local LLM
    func summarize(text: String) async throws -> String
    
    /// Categorize transcript (returns category name)
    func categorize(text: String) async throws -> String
    
    /// Generate custom prompt response
    func generate(prompt: String, context: String) async throws -> String
    
    /// Whether LLM is available and initialized
    var isAvailable: Bool { get }
    
    /// Model name currently in use
    var modelName: String { get }
}

// MARK: - Context & Data Models

/// Metadata passed to formatters and destinations
struct TranscriptContext {
    /// The full transcript text
    let transcript: String
    
    /// When the transcript was created
    let date: Date
    
    /// Name of the Whisper model used
    let model: String
    
    /// Duration of the recording in seconds
    let duration: TimeInterval
    
    /// Path to the original audio file
    let audioURL: URL
    
    /// Additional metadata (extensible)
    var metadata: [String: Any] = [:]
}

// TranscriptEntry is defined in Models/TranscriptEntry.swift
// (including speakerSegments field for diarization)

// MARK: - Capture Configuration

enum CaptureMode: String, CaseIterable, Codable {
    case micOnly = "mic"
    case systemOnly = "system"
    case both = "both"
    
    var usesMicrophone: Bool {
        self == .micOnly || self == .both
    }
    
    var usesSystemAudio: Bool {
        self == .systemOnly || self == .both
    }
    
    var displayName: String {
        switch self {
        case .micOnly:
            return "Microphone Only"
        case .systemOnly:
            return "System Audio Only"
        case .both:
            return "Both (Mic + System)"
        }
    }
}

// MARK: - Diarization Data

struct SpeakerSegment: Codable {
    /// Speaker label (e.g., "Speaker 1", "Speaker 2")
    let speaker: String
    
    /// Start time in seconds
    let startTime: TimeInterval
    
    /// End time in seconds
    let endTime: TimeInterval
    
    var duration: TimeInterval {
        endTime - startTime
    }
}

// MARK: - Plugin Errors

enum PluginError: LocalizedError {
    case loadFailed(String)
    case initializationFailed(String)
    case serviceNotFound(String)
    case dependencyMissing(String)
    case permissionDenied(String)
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .loadFailed(let msg):
            return "Failed to load plugin: \(msg)"
        case .initializationFailed(let msg):
            return "Plugin initialization failed: \(msg)"
        case .serviceNotFound(let id):
            return "Service not found: \(id)"
        case .dependencyMissing(let dep):
            return "Required service missing: \(dep)"
        case .permissionDenied(let reason):
            return "Permission denied: \(reason)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

// MARK: - System Audio Errors

enum SystemAudioError: LocalizedError {
    case unavailable(String)
    case permissionDenied
    case captureAlreadyActive
    case captureNotActive
    case captureFailed(String)
    case encodingFailed(String)
    case unsupportedOS
    
    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return "System audio unavailable: \(reason)"
        case .permissionDenied:
            return "Screen recording permission not granted"
        case .captureAlreadyActive:
            return "Audio capture already active"
        case .captureNotActive:
            return "No active audio capture to stop"
        case .captureFailed(let reason):
            return "Capture failed: \(reason)"
        case .encodingFailed(let reason):
            return "Audio encoding failed: \(reason)"
        case .unsupportedOS:
            return "ScreenCaptureKit requires macOS 13.0 or later"
        }
    }
}

// MARK: - Diarization Errors

enum DiarizationError: LocalizedError {
    case modelNotLoaded
    case analysisFailedError(String)
    case audioTooShort
    case unsupportedAudioFormat(String)
    case pythonNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Diarization model not loaded"
        case .analysisFailedError(let reason):
            return "Speaker diarization failed: \(reason)"
        case .audioTooShort:
            return "Audio duration too short for reliable diarization"
        case .unsupportedAudioFormat(let format):
            return "Unsupported audio format: \(format)"
        case .pythonNotAvailable:
            return "Python runtime not available for diarization"
        }
    }
}

// MARK: - LLM Errors

enum LLMError: LocalizedError {
    case notAvailable(String)
    case modelLoadFailed(String)
    case generationFailed(String)
    case connectionFailed(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notAvailable(let reason):
            return "LLM not available: \(reason)"
        case .modelLoadFailed(let model):
            return "Failed to load model: \(model)"
        case .generationFailed(let reason):
            return "Text generation failed: \(reason)"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .invalidResponse:
            return "Invalid response from LLM"
        }
    }
}
