import Foundation

@MainActor
class SonioxTranscriptionService {
    private let apiBase = "https://api.soniox.com/v1"
    private let session = SecureURLSession.makeEphemeral()
    
    // Polling configuration with exponential backoff
    private let initialPollingInterval: TimeInterval = 1.0  // Start with 1 second
    private let maxPollingInterval: TimeInterval = 10.0     // Cap at 10 seconds
    private let pollingBackoffMultiplier: Double = 1.5      // Increase by 50% each iteration
    private let maxWaitSeconds: TimeInterval = 120          // 2 minutes max (reduced from 5 minutes)
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)
        
        let fileId = try await uploadFile(audioURL: audioURL, apiKey: config.apiKey)
        let transcriptionId = try await createTranscription(fileId: fileId, apiKey: config.apiKey, modelName: model.name)
        try await pollTranscriptionStatus(id: transcriptionId, apiKey: config.apiKey)
        let transcript = try await fetchTranscript(id: transcriptionId, apiKey: config.apiKey)
        
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudTranscriptionError.noTranscriptionReturned
        }
        return transcript
    }
    
    private func getAPIConfig(for model: any TranscriptionModel) throws -> APIConfig {
        let keychain = KeychainManager()
        guard let apiKey = keychain.getAPIKey(for: "Soniox"), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }
        return APIConfig(apiKey: apiKey)
    }
    
    private func uploadFile(audioURL: URL, apiKey: String) async throws -> String {
        guard let apiURL = URL(string: "\(apiBase)/files") else {
            throw CloudTranscriptionError.dataEncodingError
        }
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = try createMultipartBody(fileURL: audioURL, boundary: boundary)
        let (data, response) = try await session.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        do {
            let uploadResponse = try JSONDecoder().decode(FileUploadResponse.self, from: data)
            return uploadResponse.id
        } catch {
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    private func createTranscription(fileId: String, apiKey: String, modelName: String) async throws -> String {
        guard let apiURL = URL(string: "\(apiBase)/transcriptions") else {
            throw CloudTranscriptionError.dataEncodingError
        }
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Determine the best model to use - prefer stt-async-v3 for optimal accuracy
        let effectiveModel = resolveModelName(modelName)
        
        var payload: [String: Any] = [
            "file_id": fileId,
            "model": effectiveModel,
            // Disable diarization as per app requirement
            "enable_speaker_diarization": false,
            // Enable punctuation and formatting for better output
            "enable_punctuation": true,
            "enable_profanity_filter": false  // Keep original text
        ]
        
        // Attach custom vocabulary terms from the app's dictionary (if any)
        let dictionaryTerms = getCustomDictionaryTerms()
        if !dictionaryTerms.isEmpty {
            payload["context"] = [
                "terms": dictionaryTerms
            ]
        }
        
        // Language detection settings
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        if selectedLanguage != "auto" && !selectedLanguage.isEmpty {
            payload["language_hints"] = [selectedLanguage]
        } else {
            // Enable automatic language detection when no specific language is set
            payload["enable_language_detection"] = true
        }
        
        AppLogger.transcription.debug("Soniox: Creating transcription with model '\(effectiveModel)'")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        do {
            let createResponse = try JSONDecoder().decode(CreateTranscriptionResponse.self, from: data)
            return createResponse.id
        } catch {
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }
    
    private func pollTranscriptionStatus(id: String, apiKey: String) async throws {
        guard let baseURL = URL(string: "\(apiBase)/transcriptions/\(id)") else {
            throw CloudTranscriptionError.dataEncodingError
        }
        let start = Date()
        var currentInterval = initialPollingInterval
        var pollCount = 0
        
        AppLogger.transcription.debug("Soniox: Starting to poll transcription status for id '\(id)'")
        
        while true {
            pollCount += 1
            var request = URLRequest(url: baseURL)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
                AppLogger.transcription.error("Soniox: Poll request failed with status \(httpResponse.statusCode): \(errorMessage)")
                throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
            do {
                let status = try JSONDecoder().decode(TranscriptionStatusResponse.self, from: data)
                switch status.status.lowercased() {
                case "completed":
                    let elapsed = Date().timeIntervalSince(start)
                    AppLogger.transcription.info("Soniox: Transcription completed after \(pollCount) polls (\(String(format: "%.1f", elapsed))s)")
                    return
                case "failed":
                    let errorMsg = status.errorMessage ?? "Transcription failed"
                    AppLogger.transcription.error("Soniox: Transcription failed: \(errorMsg)")
                    throw CloudTranscriptionError.apiRequestFailed(statusCode: 500, message: errorMsg)
                case "processing", "pending", "queued":
                    // Expected states, continue polling
                    break
                default:
                    AppLogger.transcription.debug("Soniox: Unknown status '\(status.status)', continuing to poll")
                }
            } catch let decodingError as DecodingError {
                // Log decoding errors but continue polling
                AppLogger.transcription.warning("Soniox: Failed to decode status response: \(decodingError.localizedDescription)")
            }
            
            // Check timeout
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > maxWaitSeconds {
                AppLogger.transcription.error("Soniox: Transcription timed out after \(String(format: "%.1f", elapsed))s (\(pollCount) polls)")
                throw CloudTranscriptionError.apiRequestFailed(statusCode: 504, message: "Transcription timed out after \(Int(elapsed)) seconds")
            }
            
            // Exponential backoff sleep
            let sleepNanoseconds = UInt64(currentInterval * 1_000_000_000)
            try await Task.sleep(nanoseconds: sleepNanoseconds)
            
            // Increase interval for next iteration (with cap)
            currentInterval = min(currentInterval * pollingBackoffMultiplier, maxPollingInterval)
        }
    }
    
    /// Resolves the model name to use the best available Soniox model
    private func resolveModelName(_ modelName: String) -> String {
        // If user explicitly specified a model, use it
        let lowercased = modelName.lowercased()
        if lowercased.contains("stt-async") || lowercased.contains("stt-rt") {
            return modelName
        }
        
        // Default to the latest async model for best accuracy
        // stt-async-v3 is the latest and most accurate model as of 2024
        return "stt-async-v3"
    }
    
    private func fetchTranscript(id: String, apiKey: String) async throws -> String {
        guard let apiURL = URL(string: "\(apiBase)/transcriptions/\(id)/transcript") else {
            throw CloudTranscriptionError.dataEncodingError
        }
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTranscriptionError.networkError(URLError(.badServerResponse))
        }
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            throw CloudTranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        if let decoded = try? JSONDecoder().decode(TranscriptResponse.self, from: data) {
            return decoded.text
        }
        if let asString = String(data: data, encoding: .utf8), !asString.isEmpty {
            return asString
        }
        throw CloudTranscriptionError.noTranscriptionReturned
    }
    
    private func createMultipartBody(fileURL: URL, boundary: String) throws -> Data {
        var body = Data()
        let crlf = "\r\n"
        guard let audioData = try? Data(contentsOf: fileURL) else {
            throw CloudTranscriptionError.audioFileNotFound
        }
        body.append(Data("--\(boundary)\(crlf)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\(crlf)".utf8))
        body.append(Data("Content-Type: audio/wav\(crlf)\(crlf)".utf8))
        body.append(audioData)
        body.append(Data(crlf.utf8))
        body.append(Data("--\(boundary)--\(crlf)".utf8))
        return body
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
        for w in words {
            let key = w.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(w)
            }
        }
        return unique
    }
    
    private struct APIConfig { let apiKey: String }
    private struct FileUploadResponse: Decodable { let id: String }
    private struct CreateTranscriptionResponse: Decodable { let id: String }
    private struct TranscriptionStatusResponse: Decodable {
        let status: String
        let errorMessage: String?
        
        enum CodingKeys: String, CodingKey {
            case status
            case errorMessage = "error_message"
        }
    }
    private struct TranscriptResponse: Decodable { let text: String }
}
