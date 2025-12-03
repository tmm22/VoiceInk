import Foundation
import OSLog

@MainActor
class ElevenLabsTranscriptionService {
    private let session = SecureURLSession.makeEphemeral()
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try prepareRequest(for: model, audioURL: audioURL)
        
        AppLogger.network.info("Sending transcription request to ElevenLabs using model: \(model.name)")
        
        let (data, response) = try await session.upload(for: config.request, from: config.body)
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.network.error("ElevenLabs: Invalid HTTP response")
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            AppLogger.network.error("ElevenLabs API request failed with status \(httpResponse.statusCode): \(errorMessage)")
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            AppLogger.network.info("Successfully received transcription from ElevenLabs")
            return transcriptionResponse.text
        } catch {
            AppLogger.network.error("Failed to decode ElevenLabs API response: \(error.localizedDescription)")
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
        
        AppLogger.network.debug("Configured ElevenLabs with model: \(model.name), version: \(version)")
        
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
        
        body.append(Data("--\(boundary)--\(crlf)".utf8))
        return body
    }

    private func appendFormField(
        data: inout Data,
        boundary: String,
        name: String,
        value: String
    ) {
        let crlf = "\r\n"
        data.append(Data("--\(boundary)\(crlf)".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)".utf8))
        data.append(Data(value.utf8))
        data.append(Data(crlf.utf8))
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
        data.append(Data("--\(boundary)\(crlf)".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\(crlf)".utf8))
        data.append(Data("Content-Type: \(contentType)\(crlf)\(crlf)".utf8))
        data.append(value)
        data.append(Data(crlf.utf8))
    }

    private func resolvedLanguageCode() -> String? {
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        
        // For ElevenLabs, we'll use language detection for "auto" mode with V2 models
        // For V1 models or specific language selection, we'll pass the language code
        if selectedLanguage == "auto" || selectedLanguage.isEmpty {
            AppLogger.network.debug("Using auto language detection for ElevenLabs")
            return nil
        } else {
            AppLogger.network.debug("Using specific language for ElevenLabs: \(selectedLanguage)")
            return selectedLanguage
        }
    }

    private func fetchAPIKey() throws -> String {
        let keychain = KeychainManager()
        guard let apiKey = keychain.getAPIKey(for: "ElevenLabs"), !apiKey.isEmpty else {
            AppLogger.network.error("Missing ElevenLabs API key")
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

private enum ElevenLabsModelVersion: CustomStringConvertible {
    case scribeV1
    case scribeV2
    case scribeV2Realtime
    case unknown
    
    init(modelName: String) {
        let lowercased = modelName.lowercased()
        
        // First check for specific model variants
        if lowercased.contains("v2_realtime") || lowercased.contains("v2-realtime") ||
           (lowercased.contains("v2") && lowercased.contains("realtime")) {
            self = .scribeV2Realtime
        }
        // Then check for general v2 models
        else if lowercased.contains("v2") || lowercased == "scribe_v2" {
            self = .scribeV2
        }
        // Then check for v1 models
        else if lowercased.contains("scribe") || lowercased == "scribe_v1" {
            self = .scribeV1
        }
        // Default to unknown
        else {
            AppLogger.network.warning("Unknown ElevenLabs model name: \(modelName), defaulting to scribeV2")
            self = .scribeV2 // Default to V2 for unknown models
        }
    }
    
    var description: String {
        switch self {
        case .scribeV1: return "Scribe V1"
        case .scribeV2: return "Scribe V2"
        case .scribeV2Realtime: return "Scribe V2 Realtime"
        case .unknown: return "Unknown (using Scribe V2)"
        }
    }
    
    var endpoint: URL {
        switch self {
        case .scribeV2, .scribeV2Realtime:
            return URL(string: "https://api.elevenlabs.io/v2/speech-to-text") ?? Self.fallbackEndpoint
        case .scribeV1, .unknown:
            return Self.fallbackEndpoint
        }
    }
    
    private static let fallbackEndpoint: URL = {
        guard let url = URL(string: "https://api.elevenlabs.io/v1/speech-to-text") else {
            preconditionFailure("Invalid hardcoded URL - this is a programming error")
        }
        return url
    }()
    
    var preferredContentType: String {
        // VoiceInk records in WAV format, so use audio/wav for all versions
        return "audio/wav"
    }
    
    var shouldTagAudioEvents: Bool {
        switch self {
        case .scribeV2, .scribeV2Realtime:
            return true
        case .scribeV1, .unknown:
            return false
        }
    }
    
    var defaultTemperature: Double {
        switch self {
        case .scribeV2Realtime:
            return 0.1
        case .scribeV2:
            return 0.2
        case .scribeV1, .unknown:
            return 0.0
        }
    }
    
    var additionalParameters: [String: String] {
        var params: [String: String] = [:]
        
        switch self {
        case .scribeV2, .scribeV2Realtime:
            // Word-level timestamps for all V2 models
            params["timestamps_granularity"] = "word"
            params["diarize"] = "false"
            
            // Add optimal parameters for V2 models
            params["detect_language"] = "true"
            params["chunk_size"] = "30"
            
            // Add streaming parameters for realtime model
            if self == .scribeV2Realtime {
                params["streaming_latency"] = "low"
            }
            
        case .scribeV1, .unknown:
            // V1 doesn't support these parameters
            break
        }
        
        return params
    }
}