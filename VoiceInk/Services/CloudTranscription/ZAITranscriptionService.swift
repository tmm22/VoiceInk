import Foundation
import os

/// Service for transcribing audio using Z.AI's GLM-ASR API.
/// Z.AI provides the GLM-ASR-Nano-2512 model with exceptional accuracy for Chinese, English, and 14+ languages.
/// API Documentation: https://docs.z.ai/api-reference/audio/audio-transcriptions
class ZAITranscriptionService {
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "ZAIService")
    private let session = SecureURLSession.makeEphemeral()
    
    /// Transcribes audio using Z.AI's GLM-ASR API.
    /// - Parameters:
    ///   - audioURL: URL to the audio file to transcribe
    ///   - model: The transcription model to use
    /// - Returns: The transcribed text
    /// - Throws: CloudTranscriptionError if transcription fails
    /// - Note: Audio must be ≤30 seconds and file size ≤25MB
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        
        let body = try await createRequestBody(audioURL: audioURL, modelName: config.modelName, boundary: boundary)
        
        let (data, response) = try await session.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            logger.error("Z.AI API request failed with status \(httpResponse.statusCode): \(errorMessage, privacy: .public)")
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
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
    private func createRequestBody(audioURL: URL, modelName: String, boundary: String) async throws -> Data {
        var body = Data()
        let crlf = "\r\n"
        let audioData: Data
        do {
            audioData = try await AudioFileLoader.loadData(from: audioURL)
        } catch {
            throw CloudTranscriptionError.audioFileNotFound
        }
        
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
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\(crlf)".utf8))
        body.append(Data("Content-Type: \(contentType)\(crlf)\(crlf)".utf8))
        body.append(audioData)
        body.append(Data(crlf.utf8))
        
        // Model field
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"model\"\(crlf)\(crlf)".utf8))
        body.append(Data(modelName.utf8))
        body.append(Data(crlf.utf8))
        
        // Stream field (false for synchronous transcription)
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"stream\"\(crlf)\(crlf)".utf8))
        body.append(Data("false".utf8))
        body.append(Data(crlf.utf8))
        
        // Optional: Include hotwords if available from user dictionary
        // This could be enhanced to pull from the user's custom vocabulary
        
        body.append(Data("--\(boundary)--\(crlf)".utf8))
        
        return body
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
