import Foundation
import os

class GroqTranscriptionService {
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "GroqService")
    private let session = SecureURLSession.makeEphemeral()
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        
        let body = try await createOpenAICompatibleRequestBody(audioURL: audioURL, modelName: config.modelName, boundary: boundary)
        
        let (data, response) = try await session.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            logger.error("Groq API request failed with status \(httpResponse.statusCode): \(errorMessage, privacy: .public)")
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            return transcriptionResponse.text
        } catch {
            logger.error("Failed to decode Groq API response: \(error.localizedDescription)")
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    private func getAPIConfig(for model: any TranscriptionModel) throws -> APIConfig {
        let keychain = KeychainManager()
        // Try Keychain first
        guard let apiKey = keychain.getAPIKey(for: "GROQ"), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }
        
        guard let apiURL = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions") else {
            throw NSError(domain: "GroqTranscriptionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        return APIConfig(url: apiURL, apiKey: apiKey, modelName: model.name)
    }
    
    private func createOpenAICompatibleRequestBody(audioURL: URL, modelName: String, boundary: String) async throws -> Data {
        var body = Data()
        let crlf = "\r\n"
        let audioData: Data
        do {
            audioData = try await AudioFileLoader.loadData(from: audioURL)
        } catch {
            throw CloudTranscriptionError.audioFileNotFound
        }
        
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        let prompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? ""
        
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\(crlf)".utf8))
        body.append(Data("Content-Type: audio/wav\(crlf)\(crlf)".utf8))
        body.append(audioData)
        body.append(Data(crlf.utf8))
        
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"model\"\(crlf)\(crlf)".utf8))
        body.append(Data(modelName.utf8))
        body.append(Data(crlf.utf8))
        
        if selectedLanguage != "auto", !selectedLanguage.isEmpty {
            body.append(Data("--\(boundary)\(crlf)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"language\"\(crlf)\(crlf)".utf8))
            body.append(Data(selectedLanguage.utf8))
            body.append(Data(crlf.utf8))
        }
        
        // Include prompt for OpenAI-compatible APIs
        if !prompt.isEmpty {
            body.append(Data("--\(boundary)\(crlf)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"prompt\"\(crlf)\(crlf)".utf8))
            body.append(Data(prompt.utf8))
            body.append(Data(crlf.utf8))
        }
        
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"response_format\"\(crlf)\(crlf)".utf8))
        body.append(Data("json".utf8))
        body.append(Data(crlf.utf8))
        
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"temperature\"\(crlf)\(crlf)".utf8))
        body.append(Data("0".utf8))
        body.append(Data(crlf.utf8))
        body.append(Data("--\(boundary)--\(crlf)".utf8))
        
        return body
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
        let x_groq: GroqMetadata?
        
        struct GroqMetadata: Decodable {
            let id: String?
        }
    }
} 
