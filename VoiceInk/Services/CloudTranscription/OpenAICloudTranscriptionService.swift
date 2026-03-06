import Foundation
import os

final class OpenAICloudTranscriptionService: CloudTranscriptionBase, CloudTranscriptionProvider {
    let supportedProvider: ModelProvider = .openAI
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "OpenAICloudTranscriptionService")

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)

        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await uploadMultipartForm(
            request,
            audioURL: audioURL,
            fields: requestFields(modelName: config.modelName)
        )
        let responseData = try validateResponse(response, data: data, logger: logger, providerName: "OpenAI")

        do {
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: responseData)
            return transcriptionResponse.text
        } catch {
            logger.error("Failed to decode OpenAI transcription response: \(error.localizedDescription, privacy: .public)")
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }

    private func getAPIConfig(for model: any TranscriptionModel) throws -> APIConfig {
        guard let apiKey = KeychainManager.shared.getAPIKey(for: "OpenAI"), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }

        guard let apiURL = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            throw NSError(domain: "OpenAICloudTranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI API URL"])
        }

        return APIConfig(url: apiURL, apiKey: apiKey, modelName: model.name)
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
