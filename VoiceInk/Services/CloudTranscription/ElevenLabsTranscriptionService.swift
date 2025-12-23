import Foundation

class ElevenLabsTranscriptionService: CloudTranscriptionBase, CloudTranscriptionProvider {
    let supportedProvider: ModelProvider = .elevenLabs
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try await prepareRequest(for: model, audioURL: audioURL)
        
        let (data, response) = try await session.upload(for: config.request, from: config.body)
        let responseData = try validateResponse(response, data: data, providerName: "ElevenLabs")
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: responseData)
            return transcriptionResponse.text
        } catch {
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    private func prepareRequest(for model: any TranscriptionModel, audioURL: URL) async throws -> APIConfig {
        let apiKey = try fetchAPIKey()
        let version = ElevenLabsModelVersion(modelName: model.name)
        var formData = MultipartFormDataBuilder()
        var request = URLRequest(url: version.endpoint)
        request.httpMethod = "POST"
        request.setValue(formData.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        try await createRequestBody(
            audioURL: audioURL,
            modelName: model.name,
            version: version,
            formData: &formData
        )
        let body = formData.finalize()
        
        return APIConfig(request: request, body: body)
    }
    
    private func createRequestBody(
        audioURL: URL,
        modelName: String,
        version: ElevenLabsModelVersion,
        formData: inout MultipartFormDataBuilder
    ) async throws {
        let audioData = try await loadAudioData(from: audioURL)
        
        formData.addFile(
            name: "file",
            filename: audioURL.lastPathComponent,
            data: audioData,
            contentType: version.preferredContentType
        )
        formData.addField(name: "model_id", value: modelName)
        formData.addField(name: "tag_audio_events", value: version.shouldTagAudioEvents ? "true" : "false")
        formData.addField(name: "temperature", value: String(version.defaultTemperature))
        
        if let languageCode = resolvedLanguageCode() {
            formData.addField(name: "language_code", value: languageCode)
        }
        
        for (key, value) in version.additionalParameters {
            formData.addField(name: key, value: value)
        }
    }

    private func resolvedLanguageCode() -> String? {
        let selectedLanguage = AppSettings.TranscriptionSettings.selectedLanguage ?? "auto"
        return selectedLanguage == "auto" || selectedLanguage.isEmpty ? nil : selectedLanguage
    }

    private func fetchAPIKey() throws -> String {
        let keychain = KeychainManager()
        guard let apiKey = keychain.getAPIKey(for: "ElevenLabs"), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }
        return apiKey
    }
}

private struct APIConfig {
    let request: URLRequest
    let body: Data
}

private struct TranscriptionResponse: Decodable {
    let text: String
    let language: String?
    let duration: Double?
}

private enum ElevenLabsModelVersion {
    case scribeV1
    case scribeV2Realtime
    case unknown
    
    init(modelName: String) {
        let lowercased = modelName.lowercased()
        if lowercased.contains("v2") {
            self = .scribeV2Realtime
        } else if lowercased.contains("scribe") {
            self = .scribeV1
        } else {
            self = .unknown
        }
    }
    
    var endpoint: URL {
        switch self {
        case .scribeV2Realtime:
            return URL(string: "https://api.elevenlabs.io/v2/speech-to-text") ?? fallbackEndpoint
        default:
            return fallbackEndpoint
        }
    }
    
    private var fallbackEndpoint: URL {
        URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    }
    
    var preferredContentType: String {
        // VoiceInk records in WAV format, so use audio/wav for all versions
        return "audio/wav"
    }
    
    var shouldTagAudioEvents: Bool {
        switch self {
        case .scribeV2Realtime:
            return true
        default:
            return false
        }
    }
    
    var defaultTemperature: Double {
        switch self {
        case .scribeV2Realtime:
            return 0.1
        default:
            return 0.0
        }
    }
    
    var additionalParameters: [String: String] {
        var params: [String: String] = [:]
        switch self {
        case .scribeV2Realtime:
            params["timestamps_granularity"] = "word"
            params["diarize"] = "false"
        default:
            break
        }
        return params
    }
}
