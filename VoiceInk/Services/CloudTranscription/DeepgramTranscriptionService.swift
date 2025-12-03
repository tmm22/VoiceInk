import Foundation
import os

class DeepgramTranscriptionService {
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "DeepgramService")
    private let session = SecureURLSession.makeEphemeral()
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)
        
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.setValue("Token \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        
        guard let audioData = try? Data(contentsOf: audioURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }
        
        let (data, response) = try await session.upload(for: request, from: audioData)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            logger.error("Deepgram API request failed with status \(httpResponse.statusCode): \(errorMessage, privacy: .public)")
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(DeepgramResponse.self, from: data)
            
            // If diarization is enabled and we have utterances, format with speaker labels
            if config.diarizeEnabled, let utterances = transcriptionResponse.results.utterances, !utterances.isEmpty {
                return formatTranscriptWithSpeakers(utterances)
            }
            
            // Fall back to channel transcript
            guard let transcript = transcriptionResponse.results.channels.first?.alternatives.first?.transcript,
                  !transcript.isEmpty else {
                logger.error("No transcript found in Deepgram response")
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            return transcript
        } catch let error as CloudTranscriptionError {
            throw error
        } catch {
            logger.error("Failed to decode Deepgram API response: \(error.localizedDescription)")
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    // MARK: - Private Methods
    
    private func formatTranscriptWithSpeakers(_ utterances: [Utterance]) -> String {
        var formattedLines: [String] = []
        
        for utterance in utterances {
            let speaker = utterance.speaker
            let text = utterance.transcript
            formattedLines.append("Speaker \(speaker): \(text)")
        }
        
        return formattedLines.joined(separator: "\n")
    }
    
    private func getAPIConfig(for model: any TranscriptionModel) throws -> APIConfig {
        let keychain = KeychainManager()
        guard let apiKey = keychain.getAPIKey(for: "Deepgram"), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }
        
        // Check if diarization should be enabled based on model name
        let diarizeEnabled = model.name.contains("diarize")
        
        // Build the URL with query parameters
        guard var components = URLComponents(string: "https://api.deepgram.com/v1/listen") else {
            throw CloudTranscriptionError.dataEncodingError
        }
        var queryItems: [URLQueryItem] = []
        
        // Add language parameter if not auto-detect
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        
        // Choose model based on language and model name
        let deepgramModel: String
        if model.name.contains("nova-3") || model.name.contains("nova3") {
            deepgramModel = "nova-3"
        } else if model.name.contains("nova-2") || model.name.contains("nova2") {
            deepgramModel = "nova-2"
        } else {
            // Default to nova-3 for English, nova-2 for other languages
            deepgramModel = selectedLanguage == "en" ? "nova-3" : "nova-2"
        }
        queryItems.append(URLQueryItem(name: "model", value: deepgramModel))
        
        // Standard formatting options
        queryItems.append(contentsOf: [
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "paragraphs", value: "true")
        ])
        
        // Enable word-level timestamps (for future use)
        queryItems.append(URLQueryItem(name: "words", value: "true"))
        
        // Enable diarization if model name contains "diarize"
        if diarizeEnabled {
            queryItems.append(URLQueryItem(name: "diarize", value: "true"))
            queryItems.append(URLQueryItem(name: "utterances", value: "true"))
            #if DEBUG
            print("Deepgram: Diarization enabled for model \(model.name)")
            #endif
        }
        
        // Add language hint if not auto-detect
        if selectedLanguage != "auto" && !selectedLanguage.isEmpty {
            queryItems.append(URLQueryItem(name: "language", value: selectedLanguage))
        }
        
        // Add custom vocabulary (keywords) from dictionary
        let dictionaryTerms = getCustomDictionaryTerms()
        for term in dictionaryTerms {
            // URL encode the term for safe query parameter usage
            if let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                queryItems.append(URLQueryItem(name: "keywords", value: encodedTerm))
            }
        }
        
        components.queryItems = queryItems
        
        guard let apiURL = components.url else {
            throw CloudTranscriptionError.dataEncodingError
        }
        
        #if DEBUG
        print("Deepgram: Request URL: \(apiURL.absoluteString)")
        #endif
        
        return APIConfig(url: apiURL, apiKey: apiKey, modelName: model.name, diarizeEnabled: diarizeEnabled)
    }
    
    private func getCustomDictionaryTerms() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: "CustomVocabularyItems") else {
            return []
        }
        
        // Decode without depending on UI layer types; extract "word" strings
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        let words = json.compactMap { $0["word"] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // De-duplicate while preserving order
        var seen = Set<String>()
        var unique: [String] = []
        for word in words {
            let key = word.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(word)
            }
        }
        
        return unique
    }
    
    // MARK: - Response Types
    
    private struct APIConfig {
        let url: URL
        let apiKey: String
        let modelName: String
        let diarizeEnabled: Bool
    }
    
    private struct DeepgramResponse: Decodable {
        let results: Results
        
        struct Results: Decodable {
            let channels: [Channel]
            let utterances: [Utterance]?
            
            struct Channel: Decodable {
                let alternatives: [Alternative]
                
                struct Alternative: Decodable {
                    let transcript: String
                    let confidence: Double?
                    let words: [Word]?
                }
            }
        }
    }
    
    private struct Word: Decodable {
        let word: String
        let start: Double
        let end: Double
        let confidence: Double?
        let speaker: Int?
    }
    
    private struct Utterance: Decodable {
        let speaker: Int
        let transcript: String
        let start: Double?
        let end: Double?
        let confidence: Double?
    }
}