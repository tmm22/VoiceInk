import Foundation

class ElevenLabsTranscriptionService {
    private let session = SecureURLSession.makeEphemeral()
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try prepareRequest(for: model, audioURL: audioURL)
        
        let (data, response) = try await session.upload(for: config.request, from: config.body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            return transcriptionResponse.text
        } catch {
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    private func prepareRequest(for model: any TranscriptionModel, audioURL: URL) throws -> APIConfig {
        let apiKey = try fetchAPIKey()
        let version = ElevenLabsModelVersion(modelName: model.name)
        let boundary = "Boundary-\(UUID().uuidString)"
        
        var request = URLRequest(url: version.endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        let body = try createRequestBody(
            audioURL: audioURL,
            modelName: model.name,
            boundary: boundary,
            version: version
        )
        
        return APIConfig(request: request, body: body)
    }
    
    private func createRequestBody(
        audioURL: URL,
        modelName: String,
        boundary: String,
        version: ElevenLabsModelVersion
    ) throws -> Data {
        var body = Data()
        let crlf = "\r\n"
        
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }
        
        appendFormField(
            data: &body,
            boundary: boundary,
            name: "file",
            filename: audioURL.lastPathComponent,
            contentType: version.preferredContentType,
            value: audioData
        )
        
        appendFormField(data: &body, boundary: boundary, name: "model_id", value: modelName)
        appendFormField(data: &body, boundary: boundary, name: "tag_audio_events", value: version.shouldTagAudioEvents ? "true" : "false")
        appendFormField(data: &body, boundary: boundary, name: "temperature", value: String(version.defaultTemperature))
        
        if let languageCode = resolvedLanguageCode() {
            appendFormField(data: &body, boundary: boundary, name: "language_code", value: languageCode)
        }
        
        for (key, value) in version.additionalParameters {
            appendFormField(data: &body, boundary: boundary, name: key, value: value)
        }
        
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }

    private func appendFormField(
        data: inout Data,
        boundary: String,
        name: String,
        value: String
    ) {
        let crlf = "\r\n"
        data.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)".data(using: .utf8)!)
        data.append(value.data(using: .utf8)!)
        data.append(crlf.data(using: .utf8)!)
    }

    private func appendFormField(
        data: inout Data,
        boundary: String,
        name: String,
        filename: String,
        contentType: String,
        value: Data
    ) {
        let crlf = "\r\n"
        data.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\(crlf)".data(using: .utf8)!)
        data.append("Content-Type: \(contentType)\(crlf)\(crlf)".data(using: .utf8)!)
        data.append(value)
        data.append(crlf.data(using: .utf8)!)
    }

    private func resolvedLanguageCode() -> String? {
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        return selectedLanguage == "auto" || selectedLanguage.isEmpty ? nil : selectedLanguage
    }

    private func fetchAPIKey() throws -> String {
        let keychain = KeychainManager()
        if let keychainKey = keychain.getAPIKey(for: "ElevenLabs"), !keychainKey.isEmpty {
            return keychainKey
        }
        if let legacyKey = UserDefaults.standard.string(forKey: "ElevenLabsAPIKey"), !legacyKey.isEmpty {
            return legacyKey
        }
        throw CloudTranscriptionError.missingAPIKey
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