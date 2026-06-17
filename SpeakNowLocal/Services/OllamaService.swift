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

    private var isAvailableFlag = false
    
    // Default to localhost:11434 (standard Ollama port)
    init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL
        super.init()
    }
    
    // MARK: - SpeakNowService Lifecycle
    
    func initialize() async throws {
        do {
            // Verify Ollama is running and the model is available.
            try await verifyOllamaConnection()
            try await verifyModelAvailable()

            isAvailableFlag = true
            logger.info("OllamaService initialized with model: \(self.modelNameValue)")
        } catch {
            logger.error("OllamaService initialization failed: \(error)")
            throw error
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
        do {
            return try await callOllama(prompt: prompt, context: context)
        } catch {
            logger.error("Generation failed: \(error)")
            throw error
        }
    }

    // MARK: - Private Helpers

    private func verifyOllamaConnection() async throws {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.connectionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.notAvailable("Ollama not responding correctly")
        }
    }

    private func verifyModelAvailable() async throws {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.connectionFailed(error.localizedDescription)
        }

        var models: [String] = []
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let modelList = json["models"] as? [[String: Any]] {
            models = modelList.compactMap { $0["name"] as? String }
        }

        // If specific model not found, use first available or fail.
        if !models.contains(modelNameValue) {
            if let firstModel = models.first {
                modelNameValue = firstModel
                logger.info("Model \(self.modelNameValue) not found, using \(firstModel)")
            } else {
                throw LLMError.modelLoadFailed(modelNameValue)
            }
        }
    }

    private func callOllama(prompt: String, context: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/generate")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120 // 2 minute timeout for generation

        let body: [String: Any] = [
            "model": modelNameValue,
            "prompt": prompt,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.connectionFailed(error.localizedDescription)
        }

        let responseText: String
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let response = json["response"] as? String else {
                throw LLMError.invalidResponse
            }
            responseText = response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.generationFailed(error.localizedDescription)
        }

        guard !responseText.isEmpty else {
            throw LLMError.invalidResponse
        }

        return responseText
    }
}
