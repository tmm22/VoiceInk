import Foundation

class AssemblyAITranscriptionService {
    private let baseURL = "https://api.assemblyai.com/v2"
    private let session = SecureURLSession.makeEphemeral()
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let apiKey = try getAPIKey()
        
        // Step 1: Upload audio file
        let uploadURL = try await uploadAudio(audioURL: audioURL, apiKey: apiKey)
        
        // Step 2: Create transcription job
        let transcriptID = try await createTranscription(
            audioURL: uploadURL,
            apiKey: apiKey,
            model: model
        )
        
        // Step 3: Poll for completion and get result
        let transcript = try await pollForResult(transcriptID: transcriptID, apiKey: apiKey)
        
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudTranscriptionError.noTranscriptionReturned
        }
        
        return transcript
    }
    
    // MARK: - Private Methods
    
    private func getAPIKey() throws -> String {
        let keychain = KeychainManager()
        guard let apiKey = keychain.getAPIKey(for: "AssemblyAI"), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }
        return apiKey
    }
    
    private func uploadAudio(audioURL: URL, apiKey: String) async throws -> String {
        guard let uploadEndpoint = URL(string: "\(baseURL)/upload") else {
            throw CloudTranscriptionError.dataEncodingError
        }
        
        var request = URLRequest(url: uploadEndpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, fromFile: audioURL)
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain {
                throw CloudTranscriptionError.audioFileNotFound
            }
            throw error
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // Parse upload response to get upload_url
        do {
            let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
            return uploadResponse.upload_url
        } catch {
            #if DEBUG
            print("AssemblyAI: Failed to decode upload response: \(error)")
            #endif
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    private func createTranscription(
        audioURL: String,
        apiKey: String,
        model: any TranscriptionModel
    ) async throws -> String {
        guard let transcriptEndpoint = URL(string: "\(baseURL)/transcript") else {
            throw CloudTranscriptionError.dataEncodingError
        }
        
        var request = URLRequest(url: transcriptEndpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build request payload
        var payload: [String: Any] = [
            "audio_url": audioURL,
            "speaker_labels": true,  // Enable diarization
            "punctuate": true,
            "format_text": true
        ]
        
        // Set speech model based on model name
        if model.name.contains("nano") {
            payload["speech_model"] = "nano"
        } else {
            payload["speech_model"] = "best"
        }
        
        // Add language hint if not set to auto-detect
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        if selectedLanguage != "auto" && !selectedLanguage.isEmpty {
            payload["language_code"] = selectedLanguage
        } else {
            // Enable automatic language detection
            payload["language_detection"] = true
        }
        
        // Add custom vocabulary (word boost) from dictionary
        let dictionaryTerms = getCustomDictionaryTerms()
        if !dictionaryTerms.isEmpty {
            payload["word_boost"] = dictionaryTerms
            payload["boost_param"] = "high"
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // Parse response to get transcript ID
        do {
            let createResponse = try JSONDecoder().decode(TranscriptCreateResponse.self, from: data)
            return createResponse.id
        } catch {
            #if DEBUG
            print("AssemblyAI: Failed to decode create response: \(error)")
            #endif
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    private func pollForResult(transcriptID: String, apiKey: String) async throws -> String {
        guard let pollEndpoint = URL(string: "\(baseURL)/transcript/\(transcriptID)") else {
            throw CloudTranscriptionError.dataEncodingError
        }
        
        let start = Date()
        let maxWaitSeconds: TimeInterval = 300  // 5 minute timeout
        let pollInterval: UInt64 = 3_000_000_000  // 3 seconds in nanoseconds
        
        while true {
            var request = URLRequest(url: pollEndpoint)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
                throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
            // Parse status response
            do {
                let statusResponse = try JSONDecoder().decode(TranscriptStatusResponse.self, from: data)
                
                switch statusResponse.status.lowercased() {
                case "completed":
                    return formatTranscriptWithSpeakers(statusResponse)
                case "error":
                    let errorMsg = statusResponse.error ?? "Transcription failed"
                    throw CloudTranscriptionError.apiRequestFailed(statusCode: 500, message: errorMsg)
                default:
                    // queued, processing - continue polling
                    break
                }
            } catch let error as CloudTranscriptionError {
                throw error
            } catch {
                #if DEBUG
                print("AssemblyAI: Failed to decode status response: \(error)")
                #endif
                // Continue polling on decode errors
            }
            
            // Check timeout
            if Date().timeIntervalSince(start) > maxWaitSeconds {
                throw CloudTranscriptionError.apiRequestFailed(statusCode: 504, message: "Transcription timed out")
            }
            
            // Wait before next poll
            try await Task.sleep(nanoseconds: pollInterval)
        }
    }
    
    private func formatTranscriptWithSpeakers(_ response: TranscriptStatusResponse) -> String {
        // If we have utterances (speaker diarization), format with speaker labels
        if let utterances = response.utterances, !utterances.isEmpty {
            var formattedLines: [String] = []
            
            for utterance in utterances {
                let speaker = utterance.speaker ?? "Unknown"
                let text = utterance.text
                formattedLines.append("Speaker \(speaker): \(text)")
            }
            
            return formattedLines.joined(separator: "\n")
        }
        
        // Fall back to plain text if no utterances
        return response.text ?? ""
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
    
    private struct UploadResponse: Decodable {
        let upload_url: String
    }
    
    private struct TranscriptCreateResponse: Decodable {
        let id: String
    }
    
    private struct TranscriptStatusResponse: Decodable {
        let id: String
        let status: String
        let text: String?
        let error: String?
        let utterances: [Utterance]?
    }
    
    private struct Utterance: Decodable {
        let speaker: String?
        let text: String
        let start: Int?
        let end: Int?
        let confidence: Double?
    }
}
