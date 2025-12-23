import Foundation
import os

class MistralTranscriptionService: CloudTranscriptionBase, CloudTranscriptionProvider {
    let supportedProvider: ModelProvider = .mistral
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "MistralTranscriptionService")
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        logger.notice("Sending transcription request to Mistral for model: \(model.name)")
        let keychain = KeychainManager()
        // Try Keychain first
        guard let apiKey = keychain.getAPIKey(for: "Mistral"), !apiKey.isEmpty else {
            logger.error("Mistral API key is missing.")
            throw CloudTranscriptionError.missingAPIKey
        }

        guard let url = URL(string: "https://api.mistral.ai/v1/audio/transcriptions") else {
            throw NSError(domain: "MistralTranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        var formData = MultipartFormDataBuilder()
        request.setValue(formData.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        formData.addField(name: "model", value: model.name)

        // Add file data - matching Python SDK structure (no language field as it's commented out in all Python examples)
        let audioData: Data
        do {
            audioData = try await AudioFileLoader.loadData(from: audioURL)
        } catch {
            throw CloudTranscriptionError.audioFileNotFound
        }

        formData.addFile(
            name: "file",
            filename: audioURL.lastPathComponent,
            data: audioData,
            contentType: "audio/wav"
        )

        request.httpBody = formData.finalize()
        
        do {
            let (data, response) = try await session.data(for: request)
            let responseData = try validateResponse(response, data: data, logger: logger, providerName: "Mistral")

            do {
                let transcriptionResponse = try JSONDecoder().decode(MistralTranscriptionResponse.self, from: responseData)
                logger.notice("Successfully received transcription from Mistral.")
                return transcriptionResponse.text
            } catch {
                logger.error("Failed to decode Mistral response: \(error.localizedDescription)")
                throw CloudTranscriptionError.noTranscriptionReturned
            }
        } catch {
            logger.error("Mistral transcription request threw an error: \(error.localizedDescription)")
            throw error
        }
    }
}

struct MistralTranscriptionResponse: Codable {
    let text: String
} 
