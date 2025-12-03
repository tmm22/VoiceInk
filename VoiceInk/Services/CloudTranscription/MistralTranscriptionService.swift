import Foundation

@MainActor
class MistralTranscriptionService {
    private let logger = AppLogger.transcription
    private let session = SecureURLSession.makeEphemeral()
    
    // Default model for optimal performance on Mistral
    // voxtral-mini is the latest Mistral transcription model
    private let defaultModel = "voxtral-mini"
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        
        let body = try createRequestBody(audioURL: audioURL, modelName: config.modelName, boundary: boundary)
        request.httpBody = body
        
        logger.debug("Sending transcription request to Mistral with model: \(config.modelName)")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid HTTP response from Mistral API")
                throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
                logger.error("Mistral API request failed with status \(httpResponse.statusCode): \(errorMessage)")
                throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
            do {
                let transcriptionResponse = try JSONDecoder().decode(MistralTranscriptionResponse.self, from: data)
                logger.debug("Successfully received transcription from Mistral")
                return transcriptionResponse.text
            } catch {
                logger.error("Failed to decode Mistral API response: \(error.localizedDescription)")
                throw CloudTranscriptionError.noTranscriptionReturned
            }
        } catch let error as CloudTranscriptionError {
            throw error
        } catch {
            logger.error("Mistral transcription request threw an error: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func getAPIConfig(for model: any TranscriptionModel) throws -> APIConfig {
        let keychain = KeychainManager()
        guard let apiKey = keychain.getAPIKey(for: "Mistral"), !apiKey.isEmpty else {
            logger.error("Missing Mistral API key")
            throw CloudTranscriptionError.missingAPIKey
        }
        
        guard let apiURL = URL(string: "https://api.mistral.ai/v1/audio/transcriptions") else {
            logger.error("Invalid Mistral API URL")
            throw CloudTranscriptionError.apiRequestFailed(statusCode: 0, message: "Invalid API URL")
        }
        
        // Use the provided model name if it's not empty, otherwise use the default model
        // This ensures backward compatibility with user-configured models
        let modelName = model.provider == .mistral && !model.name.isEmpty ? model.name : defaultModel
        
        logger.debug("Using model: \(modelName) for Mistral transcription")
        return APIConfig(url: apiURL, apiKey: apiKey, modelName: modelName)
    }
    
    private func createRequestBody(audioURL: URL, modelName: String, boundary: String) throws -> Data {
        var body = Data()
        let crlf = "\r\n"
        
        guard let audioData = try? Data(contentsOf: audioURL) else {
            logger.error("Audio file not found at \(audioURL.path)")
            throw CloudTranscriptionError.audioFileNotFound
        }
        
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        
        // Add file data
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\(crlf)".utf8))
        body.append(Data("Content-Type: audio/wav\(crlf)\(crlf)".utf8))
        body.append(audioData)
        body.append(Data(crlf.utf8))
        
        // Add model parameter
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"model\"\(crlf)\(crlf)".utf8))
        body.append(Data(modelName.utf8))
        body.append(Data(crlf.utf8))
        
        // Add language parameter if specified (Mistral supports language hints)
        if selectedLanguage != "auto", !selectedLanguage.isEmpty {
            body.append(Data("--\(boundary)\(crlf)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"language\"\(crlf)\(crlf)".utf8))
            body.append(Data(selectedLanguage.utf8))
            body.append(Data(crlf.utf8))
        }
        
        // Set response_format to verbose_json for detailed output with timestamps
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"response_format\"\(crlf)\(crlf)".utf8))
        body.append(Data("verbose_json".utf8))
        body.append(Data(crlf.utf8))
        
        // Set temperature to 0.0 for deterministic results
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"temperature\"\(crlf)\(crlf)".utf8))
        body.append(Data("0.0".utf8))
        body.append(Data(crlf.utf8))
        
        // Add timestamp_granularities for word-level timestamps
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"timestamp_granularities\"\(crlf)\(crlf)".utf8))
        body.append(Data("word,segment".utf8))
        body.append(Data(crlf.utf8))
        
        body.append(Data("--\(boundary)--\(crlf)".utf8))
        
        return body
    }
    
    private struct APIConfig {
        let url: URL
        let apiKey: String
        let modelName: String
    }
}

/// Response structure for Mistral transcription API
private struct MistralTranscriptionResponse: Decodable {
    let text: String
    let language: String?
    let duration: Double?
    let segments: [Segment]?
    let words: [Word]?
    
    struct Segment: Decodable {
        let id: Int
        let start: Double
        let end: Double
        let text: String
    }
    
    struct Word: Decodable {
        let word: String
        let start: Double
        let end: Double
    }
}
