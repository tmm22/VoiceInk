import Foundation
import os

// MARK: - URL Validation Errors for OpenAI-Compatible Service
enum OpenAICompatibleURLError: LocalizedError {
    case invalidURL(String)
    case insecureURL(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let message):
            return "Invalid URL: \(message)"
        case .insecureURL(let message):
            return "Insecure URL: \(message)"
        }
    }
}

class OpenAICompatibleTranscriptionService: CloudTranscriptionBase, CloudTranscriptionProvider {
    let supportedProvider: ModelProvider = .custom
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "OpenAICompatibleService")
    
    /// Validates that a custom API endpoint URL is secure (HTTPS) for use with API credentials.
    /// - Parameter urlString: The URL string to validate
    /// - Returns: A validated URL
    /// - Throws: OpenAICompatibleURLError if the URL is invalid or insecure
    private func validateSecureURL(_ urlString: String) throws -> URL {
        guard let url = URL(string: urlString) else {
            throw OpenAICompatibleURLError.invalidURL("Cannot parse URL: \(urlString)")
        }
        
        guard let host = url.host, !host.isEmpty else {
            throw OpenAICompatibleURLError.invalidURL("Missing host in URL")
        }
        
        // CRITICAL: Enforce HTTPS for any URL carrying API credentials
        // Custom transcription endpoints should always use HTTPS to protect API keys
        guard url.scheme?.lowercased() == "https" else {
            throw OpenAICompatibleURLError.insecureURL("HTTPS required for API endpoints. Custom transcription services must use https:// to protect your API key.")
        }
        
        return url
    }
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        guard let customModel = model as? CustomCloudModel else {
            throw CloudTranscriptionError.unsupportedProvider
        }
        return try await transcribe(audioURL: audioURL, model: customModel)
    }

    func transcribe(audioURL: URL, model: CustomCloudModel) async throws -> String {
        // Validate URL is secure before using with API credentials
        let url = try validateSecureURL(model.apiEndpoint)
        
        let config = APIConfig(
            url: url,
            apiKey: model.apiKey,
            modelName: model.modelName
        )
        
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await uploadMultipartForm(
            request,
            audioURL: audioURL,
            fields: requestFields(modelName: config.modelName)
        )
        let responseData = try validateResponse(response, data: data, logger: logger, providerName: "OpenAI-compatible")
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: responseData)
            return transcriptionResponse.text
        } catch {
            logger.error("Failed to decode OpenAI-compatible API response: \(error.localizedDescription, privacy: .public)")
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    private func requestFields(modelName: String) -> [MultipartFormField] {
        let selectedLanguage = AppSettings.TranscriptionSettings.selectedLanguage ?? "auto"
        let prompt = AppSettings.TranscriptionSettings.prompt ?? ""

        var fields = [MultipartFormField(name: "model", value: modelName)]
        
        if selectedLanguage != "auto", !selectedLanguage.isEmpty {
            fields.append(MultipartFormField(name: "language", value: selectedLanguage))
        }
        
        if !prompt.isEmpty {
            fields.append(MultipartFormField(name: "prompt", value: prompt))
        }
        
        fields.append(MultipartFormField(name: "response_format", value: "json"))
        fields.append(MultipartFormField(name: "temperature", value: "0"))
        return fields
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
    }
} 
