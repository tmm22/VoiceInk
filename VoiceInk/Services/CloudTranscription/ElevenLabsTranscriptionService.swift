import Foundation
import OSLog

class ElevenLabsTranscriptionService: CloudTranscriptionBase, CloudTranscriptionProvider {
    let supportedProvider: ModelProvider = .elevenLabs
    private let apiURLString = "https://api.elevenlabs.io/v1/speech-to-text"
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ElevenLabsTranscriptionService")

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: "ElevenLabs"), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }

        guard let apiURL = URL(string: apiURLString) else {
            throw CloudTranscriptionError.dataEncodingError
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await uploadMultipartForm(
            request,
            audioURL: audioURL,
            fields: requestFields(modelName: model.name)
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        do {
            let transcriptionResponse = try JSONDecoder().decode(ElevenLabsTranscriptionResponse.self, from: data)
            return transcriptionResponse.text
        } catch {
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }

    private func requestFields(modelName: String) -> [MultipartFormField] {
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        var fields = [
            MultipartFormField(name: "model_id", value: modelName),
            MultipartFormField(name: "temperature", value: "0.0"),
            MultipartFormField(name: "tag_audio_events", value: "false")
        ]

        if selectedLanguage != "auto", !selectedLanguage.isEmpty {
            fields.append(MultipartFormField(name: "language_code", value: selectedLanguage))
        }

        return fields
    }

    private struct ElevenLabsTranscriptionResponse: Decodable {
        let text: String
    }
}
