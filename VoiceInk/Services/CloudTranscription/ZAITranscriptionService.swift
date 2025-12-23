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
        var formData = MultipartFormDataBuilder()
        request.setValue(formData.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        
        try await createRequestBody(audioURL: audioURL, modelName: config.modelName, formData: &formData)
        let body = formData.finalize()
        
        let (data, response) = try await session.upload(for: request, from: body)
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
    
    /// Creates the multipart form-data request body.
    /// Z.AI uses OpenAI-compatible API format.
    private func createRequestBody(
        audioURL: URL,
        modelName: String,
        formData: inout MultipartFormDataBuilder
    ) async throws {
        let audioData = try await loadAudioData(from: audioURL)
        
        // Determine content type based on file extension
        let contentType: String
        switch audioURL.pathExtension.lowercased() {
        case "mp3":
            contentType = "audio/mpeg"
        case "wav":
            contentType = "audio/wav"
        case "m4a":
            contentType = "audio/mp4"
        case "webm":
            contentType = "audio/webm"
        default:
            contentType = "audio/wav"
        }
        
        // File field
        formData.addFile(
            name: "file",
            filename: audioURL.lastPathComponent,
            data: audioData,
            contentType: contentType
        )
        
        // Model field
        formData.addField(name: "model", value: modelName)
        
        // Stream field (false for synchronous transcription)
        formData.addField(name: "stream", value: "false")
        
        // Optional: Include hotwords if available from user dictionary
        // This could be enhanced to pull from the user's custom vocabulary
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
