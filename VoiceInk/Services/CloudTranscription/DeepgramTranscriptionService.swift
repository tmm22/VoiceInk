import Foundation
import OSLog

@MainActor
class DeepgramTranscriptionService {
    private let session = SecureURLSession.makeEphemeral()
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)
        
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.setValue("Token \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        
        guard let audioData = try? Data(contentsOf: audioURL) else {
            AppLogger.network.error("Deepgram: Audio file not found at \(audioURL.path)")
            throw CloudTranscriptionError.audioFileNotFound
        }
        
        AppLogger.network.info("Sending transcription request to Deepgram using model: \(config.modelName)")
        
        let (data, response) = try await session.upload(for: request, from: audioData)
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.network.error("Deepgram: Invalid HTTP response")
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            AppLogger.network.error("Deepgram API request failed with status \(httpResponse.statusCode): \(errorMessage)")
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(DeepgramResponse.self, from: data)
            guard let transcript = transcriptionResponse.results.channels.first?.alternatives.first?.transcript,
                  !transcript.isEmpty else {
                AppLogger.network.error("No transcript found in Deepgram response")
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            
            AppLogger.network.info("Successfully received transcription from Deepgram")
            return transcript
        } catch {
            AppLogger.network.error("Failed to decode Deepgram API response: \(error.localizedDescription)")
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    private func getAPIConfig(for model: any TranscriptionModel) throws -> APIConfig {
        let keychain = KeychainManager()
        guard let apiKey = keychain.getAPIKey(for: "Deepgram"), !apiKey.isEmpty else {
            AppLogger.network.error("Missing Deepgram API key")
            throw CloudTranscriptionError.missingAPIKey
        }
        
        // Build the URL with query parameters
        guard var components = URLComponents(string: "https://api.deepgram.com/v1/listen") else {
            AppLogger.network.error("Invalid Deepgram API URL - this is a programming error")
            throw CloudTranscriptionError.dataEncodingError
        }
        var queryItems: [URLQueryItem] = []
        
        // Add language parameter if not auto-detect
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        
        // Choose model based on content type and language
        // For medical content, use nova-3-medical if language is English
        let isMedicalContent = UserDefaults.standard.bool(forKey: "DeepgramMedicalContent")
        let modelName: String
        
        if isMedicalContent && selectedLanguage == "en" {
            modelName = "nova-3-medical"
        } else {
            // Always use nova-3 for all languages (it supports multilingual)
            modelName = "nova-3"
        }
        
        queryItems.append(URLQueryItem(name: "model", value: modelName))
        
        // Add optimal parameters for better transcription quality
        queryItems.append(contentsOf: [
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "paragraphs", value: "true"),
            URLQueryItem(name: "utterances", value: "true"),
            URLQueryItem(name: "diarize", value: "false") // Default to false, can be enabled for multi-speaker
        ])
        
        // Add language parameter if not auto-detect
        if selectedLanguage != "auto" && !selectedLanguage.isEmpty {
            queryItems.append(URLQueryItem(name: "language", value: selectedLanguage))
        }
        
        components.queryItems = queryItems
        
        guard let apiURL = components.url else {
            AppLogger.network.error("Failed to construct Deepgram API URL")
            throw CloudTranscriptionError.dataEncodingError
        }
        
        AppLogger.network.debug("Configured Deepgram with model: \(modelName), language: \(selectedLanguage)")
        return APIConfig(url: apiURL, apiKey: apiKey, modelName: modelName)
    }
    
    private struct APIConfig {
        let url: URL
        let apiKey: String
        let modelName: String
    }
    
    private struct DeepgramResponse: Decodable {
        let results: Results
        
        struct Results: Decodable {
            let channels: [Channel]
            
            struct Channel: Decodable {
                let alternatives: [Alternative]
                
                struct Alternative: Decodable {
                    let transcript: String
                    let confidence: Double?
                }
            }
        }
    }
}