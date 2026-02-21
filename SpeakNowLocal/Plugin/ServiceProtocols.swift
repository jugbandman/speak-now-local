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

/// Persistent transcript entry
struct TranscriptEntry: Codable {
    let id: UUID
    let date: Date
    let text: String
    let model: String
    let duration: TimeInterval
    
    init(date: Date, text: String, model: String, duration: TimeInterval) {
        self.id = UUID()
        self.date = date
        self.text = text
        self.model = model
        self.duration = duration
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
