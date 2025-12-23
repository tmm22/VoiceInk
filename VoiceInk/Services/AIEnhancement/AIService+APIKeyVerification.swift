import Foundation
import os

// MARK: - API Key Verification Extension
extension AIService {
    
    /// Verifies an API key for the currently selected provider
    /// - Parameters:
    ///   - key: The API key to verify
    ///   - completion: Callback with (isValid, errorMessage)
    func verifyAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard selectedProvider.requiresAPIKey else {
            completion(true, nil)
            return
        }
        
        switch selectedProvider {
        case .anthropic:
            verifyAnthropicAPIKey(key, completion: completion)
        case .elevenLabs:
            verifyElevenLabsAPIKey(key, completion: completion)
        case .deepgram:
            verifyDeepgramAPIKey(key, completion: completion)
        case .mistral:
            verifyMistralAPIKey(key, completion: completion)
        case .soniox:
            verifySonioxAPIKey(key, completion: completion)
        case .assemblyAI:
            verifyAssemblyAIAPIKey(key, completion: completion)
        default:
            verifyOpenAICompatibleAPIKey(key, completion: completion)
        }
    }
    
    // MARK: - OpenAI Compatible Verification
    
    func verifyOpenAICompatibleAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        let selectedProvider = self.selectedProvider
        let baseURL = selectedProvider.baseURL
        let allowLocalhost = selectedProvider == .ollama
        let providerName = selectedProvider.rawValue
        let url: URL

        do {
            url = try AIProvider.validateSecureURL(baseURL, allowLocalhost: allowLocalhost)
        } catch {
            logger.error("Invalid or insecure base URL for provider: \(baseURL, privacy: .public)")
            completion(false, error.localizedDescription)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        let testBody: [String: Any] = [
            "model": currentModel,
            "messages": [
                ["role": "user", "content": "test"]
            ]
        ]
        
        // Log if JSON serialization fails (non-critical for verification)
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: testBody)
        } catch {
            logger.warning("Failed to serialize API key verification request body: \(error.localizedDescription)")
            completion(false, "Failed to create verification request")
            return
        }
        
        logger.notice("🔑 Verifying API key for \(providerName, privacy: .public) provider at \(url.absoluteString, privacy: .public)")
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.notice("🔑 API key verification failed for \(providerName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                completion(false, error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                let isValid = httpResponse.statusCode == 200
                
                if !isValid {
                    // Log and return the exact API error response
                    if let data = data, let exactAPIError = String(data: data, encoding: .utf8) {
                        self.logger.notice("🔑 API key verification failed for \(providerName, privacy: .public) - Status: \(httpResponse.statusCode) - \(exactAPIError, privacy: .public)")
                        // Truncate error message to 500 characters to prevent UI overflow
                        let truncatedError = exactAPIError.count > 500 ? String(exactAPIError.prefix(500)) + "..." : exactAPIError
                        completion(false, truncatedError)
                    } else {
                        self.logger.notice("🔑 API key verification failed for \(providerName, privacy: .public) - Status: \(httpResponse.statusCode)")
                        completion(false, "Verification failed with status code \(httpResponse.statusCode)")
                    }
                } else {
                    completion(true, nil)
                }
            } else {
                self.logger.notice("🔑 API key verification failed for \(providerName, privacy: .public): Invalid response")
                completion(false, "Invalid response from server")
            }
        }.resume()
    }
    
    // MARK: - Anthropic Verification
    
    func verifyAnthropicAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: self.selectedProvider.baseURL) else {
            logger.error("Invalid base URL for provider: \(self.selectedProvider.baseURL)")
            completion(false, "Invalid base URL for Anthropic")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(key, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let testBody: [String: Any] = [
            "model": currentModel,
            "max_tokens": 1024,
            "system": "You are a test system.",
            "messages": [
                ["role": "user", "content": "test"]
            ]
        ]
        
        // Log if JSON serialization fails (non-critical for verification)
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: testBody)
        } catch {
            logger.warning("Failed to serialize Anthropic API key verification request body: \(error.localizedDescription)")
            completion(false, "Failed to create verification request")
            return
        }
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    completion(true, nil)
                } else {
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        // Truncate error message to 500 characters to prevent UI overflow
                        let truncatedError = responseString.count > 500 ? String(responseString.prefix(500)) + "..." : responseString
                        completion(false, truncatedError)
                    } else {
                        completion(false, "Verification failed with status code \(httpResponse.statusCode)")
                    }
                }
            } else {
                completion(false, "Invalid response from server")
            }
        }.resume()
    }
    
    // MARK: - ElevenLabs Verification
    
    func verifyElevenLabsAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "https://api.elevenlabs.io/v1/user") else {
            logger.error("Invalid ElevenLabs API URL")
            completion(false, "Invalid ElevenLabs API URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(key, forHTTPHeaderField: "xi-api-key")

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            
            let isValid = (response as? HTTPURLResponse)?.statusCode == 200

            if let data = data, let body = String(data: data, encoding: .utf8) {
                self.logger.info("ElevenLabs verification response: \(body)")
                if !isValid {
                    // Truncate error message to 500 characters to prevent UI overflow
                    let truncatedError = body.count > 500 ? String(body.prefix(500)) + "..." : body
                    completion(false, truncatedError)
                    return
                }
            }

            completion(isValid, nil)
        }.resume()
    }
    
    // MARK: - Mistral Verification
    
    func verifyMistralAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "https://api.mistral.ai/v1/models") else {
            logger.error("Invalid Mistral API URL")
            completion(false, "Invalid Mistral API URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Mistral API key verification failed: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    completion(true, nil)
                } else {
                    if let data = data, let body = String(data: data, encoding: .utf8) {
                        self.logger.error("Mistral API key verification failed with status code \(httpResponse.statusCode): \(body)")
                        // Truncate error message to 500 characters to prevent UI overflow
                        let truncatedError = body.count > 500 ? String(body.prefix(500)) + "..." : body
                        completion(false, truncatedError)
                    } else {
                        self.logger.error("Mistral API key verification failed with status code \(httpResponse.statusCode) and no response body.")
                        completion(false, "Verification failed with status code \(httpResponse.statusCode)")
                    }
                }
            } else {
                self.logger.error("Mistral API key verification failed: Invalid response from server.")
                completion(false, "Invalid response from server")
            }
        }.resume()
    }

    // MARK: - Deepgram Verification
    
    func verifyDeepgramAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "https://api.deepgram.com/v1/auth/token") else {
            logger.error("Invalid Deepgram API URL")
            completion(false, "Invalid Deepgram API URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Token \(key)", forHTTPHeaderField: "Authorization")
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Deepgram API key verification failed: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    completion(true, nil)
                } else {
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        // Truncate error message to 500 characters to prevent UI overflow
                        let truncatedError = responseString.count > 500 ? String(responseString.prefix(500)) + "..." : responseString
                        completion(false, truncatedError)
                    } else {
                        completion(false, "Verification failed with status code \(httpResponse.statusCode)")
                    }
                }
            } else {
                completion(false, "Invalid response from server")
            }
        }.resume()
    }
    
    // MARK: - Soniox Verification
    
    func verifySonioxAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "https://api.soniox.com/v1/files") else {
            completion(false, "Invalid Soniox API URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Soniox API key verification failed: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    completion(true, nil)
                } else {
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        // Truncate error message to 500 characters to prevent UI overflow
                        let truncatedError = responseString.count > 500 ? String(responseString.prefix(500)) + "..." : responseString
                        completion(false, truncatedError)
                    } else {
                        completion(false, "Verification failed with status code \(httpResponse.statusCode)")
                    }
                }
            } else {
                completion(false, "Invalid response from server")
            }
        }.resume()
    }
    
    // MARK: - AssemblyAI Verification
    
    func verifyAssemblyAIAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "https://api.assemblyai.com/v2/transcript") else {
            logger.error("Invalid AssemblyAI API URL")
            completion(false, "Invalid AssemblyAI API URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(key, forHTTPHeaderField: "authorization")
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("AssemblyAI API key verification failed: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                // AssemblyAI returns 200 for valid API keys (returns list of transcripts)
                // Returns 401 for invalid keys
                let isValid = httpResponse.statusCode == 200
                if isValid {
                    completion(true, nil)
                } else {
                    if let data = data, let body = String(data: data, encoding: .utf8) {
                        self.logger.error("AssemblyAI API key verification failed with status \(httpResponse.statusCode): \(body)")
                        // Truncate error message to 500 characters to prevent UI overflow
                        let truncatedError = body.count > 500 ? String(body.prefix(500)) + "..." : body
                        completion(false, truncatedError)
                    } else {
                        completion(false, "Verification failed with status code \(httpResponse.statusCode)")
                    }
                }
            } else {
                completion(false, "Invalid response from server")
            }
        }.resume()
    }
}
