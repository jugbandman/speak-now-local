import Foundation
import os

/// LLM service using Ollama (local inference)
/// Provides summarization, categorization, and text generation
class OllamaService: NSObject, LLMService {
    // MARK: - SpeakNowService Protocol
    
    let id: String = "com.llm.ollama"
    let version: String = "1.0.0"
    
    // MARK: - Properties
    
    private let baseURL: URL
    private var modelNameValue: String = "mistral"
    private let logger = Logger(subsystem: "com.speaknow.local", category: "OllamaService")
    private let llmQueue = DispatchQueue(label: "com.speaknow.llm.ollama")
    
    private var isAvailableFlag = false
    
    // Default to localhost:11434 (standard Ollama port)
    init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL
        super.init()
    }
    
    // MARK: - SpeakNowService Lifecycle
    
    func initialize() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            llmQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: LLMError.notAvailable("Self deallocated"))
                    return
                }
                
                do {
                    // Verify Ollama is running
                    try self.verifyOllamaConnection()
                    
                    // Verify model is available
                    try self.verifyModelAvailable()
                    
                    self.isAvailableFlag = true
                    self.logger.info("OllamaService initialized with model: \(self.modelNameValue)")
                    continuation.resume()
                } catch {
                    self.logger.error("OllamaService initialization failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func cleanup() async throws {
        // No cleanup needed for Ollama
        isAvailableFlag = false
        logger.info("OllamaService cleaned up")
    }
    
    // MARK: - LLMService Protocol
    
    var isAvailable: Bool {
        isAvailableFlag
    }
    
    var modelName: String {
        modelNameValue
    }
    
    func summarize(text: String) async throws -> String {
        let prompt = """
        Summarize the following transcript in 2-3 sentences. Be concise and focus on key points:
        
        \(text)
        """
        
        return try await generate(prompt: prompt, context: "")
    }
    
    func categorize(text: String) async throws -> String {
        let prompt = """
        Categorize this transcript into ONE of these categories: Meeting, Interview, Standup, One-on-one, Presentation, Other
        Respond with only the category name, nothing else.
        
        Transcript: \(text)
        """
        
        let response = try await generate(prompt: prompt, context: "")
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func generate(prompt: String, context: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            llmQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: LLMError.notAvailable("Self deallocated"))
                    return
                }
                
                do {
                    let response = try self.callOllama(prompt: prompt, context: context)
                    continuation.resume(returning: response)
                } catch {
                    self.logger.error("Generation failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func verifyOllamaConnection() throws {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
        var connectionError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                connectionError = LLMError.connectionFailed(error.localizedDescription)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                connectionError = LLMError.notAvailable("Ollama not responding correctly")
                return
            }
        }.resume()
        
        _ = semaphore.wait(timeout: .now() + 10)
        
        if let error = connectionError {
            throw error
        }
    }
    
    private func verifyModelAvailable() throws {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        
        var models: [String] = []
        var modelError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                modelError = error
                return
            }
            
            guard let data = data else {
                modelError = LLMError.invalidResponse
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let modelList = json["models"] as? [[String: Any]] {
                    models = modelList.compactMap { $0["name"] as? String }
                }
            } catch {
                modelError = error
            }
        }.resume()
        
        _ = semaphore.wait(timeout: .now() + 10)
        
        if let error = modelError {
            throw error
        }
        
        // If specific model not found, use first available or mistral
        if !models.contains(self.modelNameValue) {
            if let firstModel = models.first {
                self.modelNameValue = firstModel
                self.logger.info("Model \(self.modelNameValue) not found, using \(firstModel)")
            } else {
                throw LLMError.modelLoadFailed(self.modelNameValue)
            }
        }
    }
    
    private func callOllama(prompt: String, context: String) throws -> String {
        let url = baseURL.appendingPathComponent("api/generate")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        let body: [String: Any] = [
            "model": modelNameValue,
            "prompt": prompt,
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        var responseText = ""
        var requestError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                requestError = LLMError.connectionFailed(error.localizedDescription)
                return
            }
            
            guard let data = data else {
                requestError = LLMError.invalidResponse
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let response = json["response"] as? String {
                    responseText = response.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    requestError = LLMError.invalidResponse
                }
            } catch {
                requestError = LLMError.generationFailed(error.localizedDescription)
            }
        }.resume()
        
        _ = semaphore.wait(timeout: .now() + 120) // 2 minute timeout
        
        if let error = requestError {
            throw error
        }
        
        guard !responseText.isEmpty else {
            throw LLMError.invalidResponse
        }
        
        return responseText
    }
}
