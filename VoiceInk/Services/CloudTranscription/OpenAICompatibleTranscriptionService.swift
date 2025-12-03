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

class OpenAICompatibleTranscriptionService {
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "OpenAICompatibleService")
    private let session = SecureURLSession.makeEphemeral()
    
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
    
    func transcribe(audioURL: URL, model: CustomCloudModel) async throws -> String {
        // Validate URL is secure before using with API credentials
        let url = try validateSecureURL(model.apiEndpoint)
        
        let config = APIConfig(
            url: url,
            apiKey: model.apiKey,
            modelName: model.modelName
        )
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        
        let body = try createOpenAICompatibleRequestBody(audioURL: audioURL, modelName: config.modelName, boundary: boundary)
        
        let (data, response) = try await session.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            logger.error("OpenAI-compatible API request failed with status \(httpResponse.statusCode): \(errorMessage, privacy: .public)")
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            return transcriptionResponse.text
        } catch {
            logger.error("Failed to decode OpenAI-compatible API response: \(error.localizedDescription)")
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    private func createOpenAICompatibleRequestBody(audioURL: URL, modelName: String, boundary: String) throws -> Data {
        var body = Data()
        let crlf = "\r\n"
        
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }
        
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        let prompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? ""
        
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\(crlf)".utf8))
        body.append(Data("Content-Type: audio/wav\(crlf)\(crlf)".utf8))
        body.append(audioData)
        body.append(Data(crlf.utf8))
        
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"model\"\(crlf)\(crlf)".utf8))
        body.append(Data(modelName.utf8))
        body.append(Data(crlf.utf8))
        
        if selectedLanguage != "auto", !selectedLanguage.isEmpty {
            body.append(Data("--\(boundary)\(crlf)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"language\"\(crlf)\(crlf)".utf8))
            body.append(Data(selectedLanguage.utf8))
            body.append(Data(crlf.utf8))
        }
        
        // Include prompt for OpenAI-compatible APIs
        if !prompt.isEmpty {
            body.append(Data("--\(boundary)\(crlf)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"prompt\"\(crlf)\(crlf)".utf8))
            body.append(Data(prompt.utf8))
            body.append(Data(crlf.utf8))
        }
        
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"response_format\"\(crlf)\(crlf)".utf8))
        body.append(Data("json".utf8))
        body.append(Data(crlf.utf8))
        
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"temperature\"\(crlf)\(crlf)".utf8))
        body.append(Data("0".utf8))
        body.append(Data(crlf.utf8))
        body.append(Data("--\(boundary)--\(crlf)".utf8))
        
        return body
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