import Foundation
import os

/// Service for transcribing audio using Z.AI's GLM-ASR API.
/// Z.AI provides the GLM-ASR-Nano-2512 model with exceptional accuracy for Chinese, English, and 14+ languages.
/// API Documentation: https://docs.z.ai/api-reference/audio/audio-transcriptions
class ZAITranscriptionService: CloudTranscriptionBase, CloudTranscriptionProvider {
    let supportedProvider: ModelProvider = .zai
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "ZAIService")
    
    /// Transcribes audio using Z.AI's GLM-ASR API.
    /// - Parameters:
    ///   - audioURL: URL to the audio file to transcribe
    ///   - model: The transcription model to use
    /// - Returns: The transcribed text
    /// - Throws: CloudTranscriptionError if transcription fails
    /// - Note: Audio must be ≤30 seconds and file size ≤25MB
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)
        
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await uploadMultipartForm(
            request,
            audioURL: audioURL,
            fields: requestFields(modelName: config.modelName)
        )
        let responseData = try validateResponse(response, data: data, logger: logger, providerName: "Z.AI")
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: responseData)
            return transcriptionResponse.text
        } catch {
            logger.error("Failed to decode Z.AI API response: \(error.localizedDescription)")
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    /// Retrieves the API configuration from Keychain.
    private func getAPIConfig(for model: any TranscriptionModel) throws -> APIConfig {
        let keychain = KeychainManager()
        guard let apiKey = keychain.getAPIKey(for: "ZAI"), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }
        
        guard let apiURL = URL(string: "https://api.z.ai/api/paas/v4/audio/transcriptions") else {
            throw NSError(domain: "ZAITranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        return APIConfig(url: apiURL, apiKey: apiKey, modelName: model.name)
    }
    
    private func requestFields(modelName: String) -> [MultipartFormField] {
        [
            MultipartFormField(name: "model", value: modelName),
            MultipartFormField(name: "stream", value: "false")
        ]
    }
    
    // MARK: - Supporting Types
    
    private struct APIConfig {
        let url: URL
        let apiKey: String
        let modelName: String
    }
    
    /// Response structure for Z.AI's audio transcription API.
    /// Compatible with OpenAI's transcription response format.
    private struct TranscriptionResponse: Decodable {
        let text: String
        let id: String?
        let created: Int?
        let model: String?
        let request_id: String?
    }
}
