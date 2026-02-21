import Foundation

// MARK: - Plugin Registry

/// Central registry for all services and plugins
@MainActor
class PluginRegistry: ObservableObject {
    static let shared = PluginRegistry()
    
    @Published var loadedPlugins: [String: SpeakNowService] = [:]
    @Published var outputServices: [OutputService] = []
    @Published var destinationServices: [DestinationService] = []
    
    private var audioService: AudioService?
    private var transcriptionService: TranscriptionService?
    private var storageService: StorageService?
    
    private init() {}
    
    // MARK: - Registration
    
    /// Register a service for a given type
    func register<T: SpeakNowService>(_ service: T) throws {
        guard loadedPlugins[service.id] == nil else {
            throw PluginError.loadFailed("Service already registered: \(service.id)")
        }
        
        loadedPlugins[service.id] = service
        
        // Also index by protocol type
        if let audio = service as? AudioService {
            audioService = audio
        }
        if let transcriber = service as? TranscriptionService {
            transcriptionService = transcriber
        }
        if let output = service as? OutputService {
            outputServices.append(output)
            outputServices.sort { $0.priority > $1.priority }
        }
        if let destination = service as? DestinationService {
            destinationServices.append(destination)
        }
        if let storage = service as? StorageService {
            storageService = storage
        }
    }
    
    // MARK: - Service Retrieval
    
    func audio() -> AudioService? {
        audioService
    }
    
    func transcription() -> TranscriptionService? {
        transcriptionService
    }
    
    func storage() -> StorageService? {
        storageService
    }
    
    func outputs() -> [OutputService] {
        outputServices
    }
    
    func destinations() -> [DestinationService] {
        destinationServices
    }
    
    func service<T: SpeakNowService>(id: String, as type: T.Type) -> T? {
        loadedPlugins[id] as? T
    }
    
    // MARK: - Plugin Management
    
    func unregister(id: String) async throws {
        guard let service = loadedPlugins[id] else {
            throw PluginError.serviceNotFound(id)
        }
        
        try await service.cleanup()
        
        loadedPlugins.removeValue(forKey: id)
        
        // Clean up indexed references
        if let audio = audioService, audio.id == id {
            audioService = nil
        }
        if let transcriber = transcriptionService, transcriber.id == id {
            transcriptionService = nil
        }
        outputServices.removeAll { $0.id == id }
        destinationServices.removeAll { $0.id == id }
    }
    
    func loadAllPlugins() async throws {
        // Initialize all loaded services
        for service in loadedPlugins.values {
            try await service.initialize()
        }
    }
    
    func unloadAll() async throws {
        for service in loadedPlugins.values {
            try await service.cleanup()
        }
        loadedPlugins.removeAll()
        audioService = nil
        transcriptionService = nil
        storageService = nil
        outputServices.removeAll()
        destinationServices.removeAll()
    }
}

// MARK: - Plugin Manifest

struct PluginManifest: Codable {
    let id: String
    let name: String
    let version: String
    let author: String
    let description: String
    let type: PluginType
    let requiredServices: [String]
    let entryPoint: String
    let isPremium: Bool
    let minimumAppVersion: String
    
    enum PluginType: String, Codable {
        case audio
        case transcription
        case output
        case destination
        case storage
    }
    
    /// Load manifest from plugin bundle
    static func load(from bundleURL: URL) throws -> PluginManifest {
        let manifestURL = bundleURL.appendingPathComponent("plugin.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        return manifest
    }
}

// MARK: - Plugin Loader

class PluginLoader {
    static let shared = PluginLoader()
    
    let pluginDirectory: URL
    
    init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.pluginDirectory = appSupport.appendingPathComponent("com.andycarlson.SpeakNowLocal/Plugins")
        
        // Create directory if needed
        try? fileManager.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
    }
    
    /// Discover all plugin bundles in the plugins directory
    func discoverPlugins() throws -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: pluginDirectory.path) else {
            return []
        }
        
        let contents = try fileManager.contentsOfDirectory(
            at: pluginDirectory,
            includingPropertiesForKeys: nil
        )
        
        return contents.filter { url in
            url.pathExtension == "bundle" || url.pathExtension == "framework"
        }
    }
    
    /// Load and instantiate plugins from discovered bundles
    func loadPlugins() async throws -> [SpeakNowService] {
        let bundleURLs = try discoverPlugins()
        var loadedServices: [SpeakNowService] = []
        
        for bundleURL in bundleURLs {
            do {
                let manifest = try PluginManifest.load(from: bundleURL)
                
                // Validate app version
                if !isCompatible(minVersion: manifest.minimumAppVersion) {
                    throw PluginError.loadFailed(
                        "\(manifest.name) requires app version \(manifest.minimumAppVersion)"
                    )
                }
                
                // TODO: Load bundle and instantiate service
                // For now, this is a placeholder
                print("Would load plugin: \(manifest.name)")
            } catch {
                print("Failed to load plugin at \(bundleURL): \(error)")
                // Continue loading other plugins
            }
        }
        
        return loadedServices
    }
    
    private func isCompatible(minVersion: String) -> Bool {
        // Parse and compare version strings
        // For now, always return true
        return true
    }
}
