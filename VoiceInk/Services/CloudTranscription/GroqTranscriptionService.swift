import Foundation
import os

class GroqTranscriptionService: CloudTranscriptionBase, CloudTranscriptionProvider {
    let supportedProvider: ModelProvider = .groq
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "GroqService")
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)
        
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        var formData = MultipartFormDataBuilder()
        request.setValue(formData.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        
        try await createOpenAICompatibleRequestBody(
            audioURL: audioURL,
            modelName: config.modelName,
            formData: &formData
        )
        let body = formData.finalize()
        
        let (data, response) = try await session.upload(for: request, from: body)
        let responseData = try validateResponse(response, data: data, logger: logger, providerName: "Groq")
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: responseData)
            return transcriptionResponse.text
        } catch {
            logger.error("Failed to decode Groq API response: \(error.localizedDescription)")
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    private func getAPIConfig(for model: any TranscriptionModel) throws -> APIConfig {
        let keychain = KeychainManager()
        // Try Keychain first
        guard let apiKey = keychain.getAPIKey(for: "GROQ"), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }
        
        guard let apiURL = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions") else {
            throw NSError(domain: "GroqTranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        return APIConfig(url: apiURL, apiKey: apiKey, modelName: model.name)
    }
    
    private func createOpenAICompatibleRequestBody(
        audioURL: URL,
        modelName: String,
        formData: inout MultipartFormDataBuilder
    ) async throws {
        let audioData = try await loadAudioData(from: audioURL)
        
        let selectedLanguage = AppSettings.TranscriptionSettings.selectedLanguage ?? "auto"
        let prompt = AppSettings.TranscriptionSettings.prompt ?? ""
        
        formData.addFile(
            name: "file",
            filename: audioURL.lastPathComponent,
            data: audioData,
            contentType: "audio/wav"
        )
        formData.addField(name: "model", value: modelName)
        
        if selectedLanguage != "auto", !selectedLanguage.isEmpty {
            formData.addField(name: "language", value: selectedLanguage)
        }
        
        // Include prompt for OpenAI-compatible APIs
        if !prompt.isEmpty {
            formData.addField(name: "prompt", value: prompt)
        }
        
        formData.addField(name: "response_format", value: "json")
        formData.addField(name: "temperature", value: "0")
    }
    
    private struct APIConfig {
        let url: URL
        let apiKey: String
        let modelName: String
    }
    
    private struct TranscriptionResponse: Decodable {
        let text: String
        let language: String?
        let duration: Double?
        let x_groq: GroqMetadata?
        
        struct GroqMetadata: Decodable {
            let id: String?
        }
    }
} 
