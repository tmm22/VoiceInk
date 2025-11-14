import Foundation

class ElevenLabsTranscriptionService {
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let version = ElevenLabsModelVersion.detect(from: model.name)
        let apiKey = try fetchAPIKey()
        let apiURL = URL(string: version.endpoint)!
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        let body = try createRequestBody(audioURL: audioURL, modelName: model.name, version: version, boundary: boundary)
        
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
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
    
    // MARK: - Helper Methods
    
    private func fetchAPIKey() throws -> String {
        guard let apiKey = UserDefaults.standard.string(forKey: "ElevenLabsAPIKey"), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }
        return apiKey
    }
    
    private func createRequestBody(audioURL: URL, modelName: String, version: ElevenLabsModelVersion, boundary: String) throws -> Data {
        var body = Data()
        let crlf = "\r\n"
        
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }
        
        // Append audio file
        appendFormField(&body, boundary: boundary, name: "file", filename: audioURL.lastPathComponent, contentType: version.preferredContentType, data: audioData)
        
        // Append model ID
        appendFormField(&body, boundary: boundary, name: "model_id", value: modelName)
        
        // Tag audio events (v2 uses this, v1 sets false)
        appendFormField(&body, boundary: boundary, name: "tag_audio_events", value: version.shouldTagAudioEvents ? "true" : "false")
        
        // Temperature
        appendFormField(&body, boundary: boundary, name: "temperature", value: "\(version.defaultTemperature)")
        
        // Language code (if not auto)
        let language = resolvedLanguageCode()
        if language != "auto" {
            appendFormField(&body, boundary: boundary, name: "language_code", value: language)
        }
        
        // Additional parameters for Scribe v2
        for (key, value) in version.additionalParameters {
            appendFormField(&body, boundary: boundary, name: key, value: value)
        }
        
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }
    
    private func appendFormField(_ body: inout Data, boundary: String, name: String, value: String) {
        let crlf = "\r\n"
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(value.data(using: .utf8)!)
        body.append(crlf.data(using: .utf8)!)
    }
    
    private func appendFormField(_ body: inout Data, boundary: String, name: String, filename: String, contentType: String, data: Data) {
        let crlf = "\r\n"
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(data)
        body.append(crlf.data(using: .utf8)!)
    }
    
    private func resolvedLanguageCode() -> String {
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        return selectedLanguage.isEmpty ? "auto" : selectedLanguage
    }
    
    // MARK: - Model Version Support
    
    private enum ElevenLabsModelVersion {
        case scribeV1
        case scribeV2Realtime
        case unknown
        
        static func detect(from modelName: String) -> ElevenLabsModelVersion {
            let name = modelName.lowercased()
            if name.contains("v2") || name.contains("realtime") {
                return .scribeV2Realtime
            } else if name.contains("v1") || name == "scribe" {
                return .scribeV1
            }
            return .unknown
        }
        
        var endpoint: String {
            switch self {
            case .scribeV1, .unknown:
                return "https://api.elevenlabs.io/v1/speech-to-text"
            case .scribeV2Realtime:
                return "https://api.elevenlabs.io/v1/speech-to-text"
            }
        }
        
        var preferredContentType: String {
            // VoiceInk records in WAV format, so use audio/wav for all versions
            return "audio/wav"
        }
        
        var shouldTagAudioEvents: Bool {
            switch self {
            case .scribeV1, .unknown:
                return false
            case .scribeV2Realtime:
                return true
            }
        }
        
        var defaultTemperature: Double {
            switch self {
            case .scribeV1, .unknown:
                return 0.0
            case .scribeV2Realtime:
                return 0.1
            }
        }
        
        var additionalParameters: [String: String] {
            switch self {
            case .scribeV1, .unknown:
                return [:]
            case .scribeV2Realtime:
                return [
                    "timestamps_granularity": "word",
                    "diarize": "false"
                ]
            }
        }
    }
    
    // MARK: - Response Models
    
    private struct TranscriptionResponse: Decodable {
        let text: String
        let language: String?
        let duration: Double?
    }
} 