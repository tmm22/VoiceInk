import Foundation
import os

class GroqTranscriptionService: CloudTranscriptionBase, CloudTranscriptionProvider {
    let supportedProvider: ModelProvider = .groq
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "GroqService")
    private let baseTimeout: TimeInterval = 120
    private let initialRetryDelay: TimeInterval = 1
    private let maxRetries: Int = 3
    
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        return try await transcribeWithRetry(audioURL: audioURL, model: model)
    }

    private func makeTranscriptionRequest(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let config = try getAPIConfig(for: model)
        
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        var formData = MultipartFormDataBuilder()
        request.setValue(formData.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = baseTimeout
        
        try await createOpenAICompatibleRequestBody(
            audioURL: audioURL,
            modelName: config.modelName,
            formData: &formData
        )
        let body = formData.finalize()
        
        let (data, response) = try await session.upload(for: request, from: body)
        let responseData = try validateResponse(response, data: data, logger: logger, providerName: "Groq")
        
        do {
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: responseData)
            return transcriptionResponse.text
        } catch {
            logger.error("Failed to decode Groq API response: \(error.localizedDescription)")
            throw CloudTranscriptionError.noTranscriptionReturned
        }
    }

    private func transcribeWithRetry(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        var retries = 0
        var currentDelay = initialRetryDelay

        while retries < self.maxRetries {
            do {
                return try await makeTranscriptionRequest(audioURL: audioURL, model: model)
            } catch let error as CloudTranscriptionError {
                switch error {
                case .networkError:
                    retries += 1
                    if retries < self.maxRetries {
                        logger.warning("Transcription request failed, retrying in \(currentDelay)s... (Attempt \(retries)/\(self.maxRetries))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        logger.error("Transcription request failed after \(self.maxRetries) retries.")
                        throw error
                    }
                case .apiRequestFailed(let statusCode, _):
                    if (500...599).contains(statusCode) || statusCode == 429 {
                        retries += 1
                        if retries < self.maxRetries {
                            logger.warning("Transcription request failed with status \(statusCode), retrying in \(currentDelay)s... (Attempt \(retries)/\(self.maxRetries))")
                            try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                            currentDelay *= 2
                        } else {
                            logger.error("Transcription request failed after \(self.maxRetries) retries.")
                            throw error
                        }
                    } else {
                        throw error
                    }
                default:
                    throw error
                }
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain &&
                   [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost].contains(nsError.code) {
                    retries += 1
                    if retries < self.maxRetries {
                        logger.warning("Transcription request failed with network error, retrying in \(currentDelay)s... (Attempt \(retries)/\(self.maxRetries))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        logger.error("Transcription request failed after \(self.maxRetries) retries with network error.")
                        throw CloudTranscriptionError.networkError(error)
                    }
                } else {
                    throw error
                }
            }
        }

        throw CloudTranscriptionError.noTranscriptionReturned
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
    
    private func createOpenAICompatibleRequestBody(
        audioURL: URL,
        modelName: String,
        formData: inout MultipartFormDataBuilder
    ) async throws {
        let audioData = try await loadAudioData(from: audioURL)
        
        let selectedLanguage = AppSettings.TranscriptionSettings.selectedLanguage ?? "auto"
        let prompt = AppSettings.TranscriptionSettings.prompt ?? ""
        
        formData.addFile(
            name: "file",
            filename: audioURL.lastPathComponent,
            data: audioData,
            contentType: "audio/wav"
        )
        formData.addField(name: "model", value: modelName)
        
        if selectedLanguage != "auto", !selectedLanguage.isEmpty {
            formData.addField(name: "language", value: selectedLanguage)
        }
        
        // Include prompt for OpenAI-compatible APIs
        if !prompt.isEmpty {
            formData.addField(name: "prompt", value: prompt)
        }
        
        formData.addField(name: "response_format", value: "json")
        formData.addField(name: "temperature", value: "0")
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
