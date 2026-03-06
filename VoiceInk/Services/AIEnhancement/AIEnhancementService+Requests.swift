import Foundation
import os

// MARK: - API Request Handling
extension AIEnhancementService {
    
    /// Makes an API request to the configured AI provider
    /// - Parameters:
    ///   - text: The text to enhance
    ///   - mode: The enhancement mode
    ///   - transcriptionModel: The transcription model used
    ///   - recordingDuration: Duration of the recording
    ///   - language: Language code
    /// - Returns: The enhanced text
    func makeRequest(
        text: String,
        mode: EnhancementPrompt,
        transcriptionModel: String,
        recordingDuration: TimeInterval,
        language: String
    ) async throws -> String {
        guard isConfigured else {
            throw EnhancementError.notConfigured
        }

        guard !text.isEmpty else {
            return ""
        }

        let formattedText = "\n<TRANSCRIPT>\n\(text)\n</TRANSCRIPT>"
        
        let systemMessage = await getSystemMessage(
            for: mode,
            transcriptionModel: transcriptionModel,
            recordingDuration: recordingDuration,
            language: language
        )
        
        self.lastSystemMessageSent = truncateForStorage(systemMessage, limit: maxStoredMessageCharacters)
        self.lastUserMessageSent = truncateForStorage(formattedText, limit: maxStoredMessageCharacters)

        logger.notice("AI Enhancement - System Message: \(systemMessage, privacy: .public)")
        
        // Handle Ollama provider separately
        if aiService.selectedProvider == .ollama {
            return try await makeOllamaRequest(formattedText: formattedText, systemMessage: systemMessage)
        }

        try await waitForRateLimit()

        do {
            switch aiService.selectedProvider {
            case .anthropic:
                return try await makeAnthropicRequest(formattedText: formattedText, systemMessage: systemMessage)
            case .openAI where AIProvider.usesResponsesAPI(for: aiService.selectedProvider, model: aiService.currentModel):
                return try await makeOpenAIResponsesRequest(formattedText: formattedText, systemMessage: systemMessage)
            default:
                return try await makeOpenAICompatibleRequest(formattedText: formattedText, systemMessage: systemMessage)
            }
        } catch let error as EnhancementError {
            if let fallbackModel = fallbackModelIfNeeded(for: error) {
                logger.warning("OpenAI model \(self.aiService.currentModel, privacy: .public) hit rate limits; retrying once with fallback model \(fallbackModel, privacy: .public)")
                if AIProvider.usesResponsesAPI(for: aiService.selectedProvider, model: fallbackModel) {
                    return try await makeOpenAIResponsesRequest(formattedText: formattedText, systemMessage: systemMessage, modelOverride: fallbackModel)
                }
                return try await makeOpenAICompatibleRequest(formattedText: formattedText, systemMessage: systemMessage, modelOverride: fallbackModel)
            }
            throw error
        }
    }
    
    /// Makes a request with retry logic for transient failures
    func makeRequestWithRetry(
        text: String,
        mode: EnhancementPrompt,
        transcriptionModel: String,
        recordingDuration: TimeInterval,
        language: String,
        maxRetries: Int = 3,
        initialDelay: TimeInterval = 1.0
    ) async throws -> String {
        var retries = 0
        var currentDelay = initialDelay

        while retries < maxRetries {
            do {
                return try await makeRequest(
                    text: text,
                    mode: mode,
                    transcriptionModel: transcriptionModel,
                    recordingDuration: recordingDuration,
                    language: language
                )
            } catch let error as EnhancementError {
                switch error {
                case .networkError, .serverError, .rateLimitExceeded:
                    retries += 1
                    if retries < maxRetries {
                        let waitTime = retryDelay(for: error, currentDelay: currentDelay)
                        logger.warning("Request failed, retrying in \(waitTime)s... (Attempt \(retries)/\(maxRetries))")
                        try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                        currentDelay = max(currentDelay * 2, waitTime * 2)
                    } else {
                        throw error
                    }
                default:
                    throw error
                }
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost].contains(nsError.code) {
                    retries += 1
                    if retries < maxRetries {
                        logger.warning("Request failed with network error, retrying in \(currentDelay)s... (Attempt \(retries)/\(maxRetries))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        throw EnhancementError.networkError
                    }
                } else {
                    throw error
                }
            }
        }
        throw EnhancementError.enhancementFailed
    }
    
    // MARK: - Provider-Specific Request Methods
    
    /// Makes a request to Ollama (local AI)
    private func makeOllamaRequest(formattedText: String, systemMessage: String) async throws -> String {
        do {
            let result = try await aiService.enhanceWithOllama(text: formattedText, systemPrompt: systemMessage, timeout: requestTimeout)
            let filteredResult = AIEnhancementOutputFilter.filter(result)
            return filteredResult
        } catch {
            if let localError = error as? LocalAIError {
                throw EnhancementError.customError(localError.errorDescription ?? "An unknown Ollama error occurred.")
            } else {
                throw EnhancementError.customError(error.localizedDescription)
            }
        }
    }
    
    /// Makes a request to Anthropic's Claude API
    private func makeAnthropicRequest(formattedText: String, systemMessage: String) async throws -> String {
        let requestBody: [String: Any] = [
            "model": aiService.currentModel,
            "max_tokens": 8192,
            "system": systemMessage,
            "messages": [
                ["role": "user", "content": formattedText]
            ]
        ]

        guard let url = URL(string: aiService.selectedProvider.baseURL) else {
            throw NSError(domain: "AIEnhancementService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(aiService.apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = requestTimeout
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw EnhancementError.customError("Failed to prepare request: \(error.localizedDescription)")
        }

        return try await executeRequest(request, parseResponse: parseAnthropicResponse)
    }
    
    /// Makes a request to OpenAI-compatible APIs (OpenAI, Groq, etc.)
    private func makeOpenAICompatibleRequest(
        formattedText: String,
        systemMessage: String,
        modelOverride: String? = nil
    ) async throws -> String {
        guard let url = URL(string: aiService.selectedProvider.baseURL) else {
            throw NSError(domain: "AIEnhancementService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(aiService.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = requestTimeout

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemMessage],
            ["role": "user", "content": formattedText]
        ]

        let selectedModel = modelOverride ?? aiService.currentModel
        let outputTokenLimit = recommendedOutputTokenLimit(for: formattedText, model: selectedModel)
        var requestBody: [String: Any] = [
            "model": selectedModel,
            "messages": messages,
            "temperature": selectedModel.lowercased().hasPrefix("gpt-5") ? 1.0 : 0.3,
            "stream": false
        ]

        if aiService.selectedProvider == .openAI {
            requestBody["store"] = false
            requestBody["max_completion_tokens"] = outputTokenLimit
        } else {
            requestBody["max_tokens"] = outputTokenLimit
        }

        if let reasoningParam = ReasoningConfig.getReasoningParameter(for: selectedModel, userPreference: reasoningEffort) {
            requestBody["reasoning_effort"] = reasoningParam
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw EnhancementError.customError("Failed to prepare request: \(error.localizedDescription)")
        }

        return try await executeRequest(request, parseResponse: parseOpenAIResponse)
    }

    private func makeOpenAIResponsesRequest(
        formattedText: String,
        systemMessage: String,
        modelOverride: String? = nil
    ) async throws -> String {
        guard let url = URL(string: AIProvider.openAIResponsesURL) else {
            throw NSError(domain: "AIEnhancementService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI Responses API URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(aiService.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = requestTimeout

        let input: [[String: Any]] = [
            ["role": "system", "content": systemMessage],
            ["role": "user", "content": formattedText]
        ]

        let selectedModel = modelOverride ?? aiService.currentModel
        var requestBody: [String: Any] = [
            "model": selectedModel,
            "input": input,
            "store": false,
            "max_output_tokens": recommendedOutputTokenLimit(for: formattedText, model: selectedModel)
        ]

        if let reasoningParam = ReasoningConfig.getReasoningParameter(for: selectedModel, userPreference: reasoningEffort) {
            requestBody["reasoning"] = ["effort": reasoningParam]
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw EnhancementError.customError("Failed to prepare request: \(error.localizedDescription)")
        }

        return try await executeRequest(request, parseResponse: parseOpenAIResponsesResponse)
    }
    
    // MARK: - Request Execution & Response Parsing
    
    /// Executes an HTTP request and parses the response
    private func executeRequest(_ request: URLRequest, parseResponse: (Data) throws -> String) async throws -> String {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw EnhancementError.invalidResponse
            }

            if httpResponse.statusCode == 200 {
                return try parseResponse(data)
            } else if httpResponse.statusCode == 429 {
                throw EnhancementError.rateLimitExceeded(
                    message: rateLimitMessage(from: data, response: httpResponse),
                    retryAfter: retryAfterInterval(from: httpResponse)
                )
            } else if (500...599).contains(httpResponse.statusCode) {
                throw EnhancementError.serverError
            } else {
                let errorString = String(data: data, encoding: .utf8) ?? "Could not decode error response."
                throw EnhancementError.customError("HTTP \(httpResponse.statusCode): \(errorString)")
            }

        } catch let error as EnhancementError {
            throw error
        } catch let error as URLError {
            throw error
        } catch {
            throw EnhancementError.customError(error.localizedDescription)
        }
    }
    
    /// Parses Anthropic API response
    private func parseAnthropicResponse(_ data: Data) throws -> String {
        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = jsonResponse["content"] as? [[String: Any]],
              let firstContent = content.first,
              let enhancedText = firstContent["text"] as? String else {
            throw EnhancementError.enhancementFailed
        }

        return AIEnhancementOutputFilter.filter(enhancedText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    /// Parses OpenAI-compatible API response
    private func parseOpenAIResponse(_ data: Data) throws -> String {
        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = jsonResponse["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let enhancedText = message["content"] as? String else {
            throw EnhancementError.enhancementFailed
        }

        return AIEnhancementOutputFilter.filter(enhancedText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func parseOpenAIResponsesResponse(_ data: Data) throws -> String {
        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EnhancementError.enhancementFailed
        }

        if let outputText = jsonResponse["output_text"] as? String,
           !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AIEnhancementOutputFilter.filter(outputText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let output = jsonResponse["output"] as? [[String: Any]] {
            let enhancedText = output
                .compactMap { item -> String? in
                    guard item["type"] as? String == "message",
                          let content = item["content"] as? [[String: Any]] else {
                        return nil
                    }

                    let text = content
                        .compactMap { $0["text"] as? String }
                        .joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    return text.isEmpty ? nil : text
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !enhancedText.isEmpty {
                return AIEnhancementOutputFilter.filter(enhancedText)
            }
        }

        throw EnhancementError.enhancementFailed
    }

    private func retryDelay(for error: EnhancementError, currentDelay: TimeInterval) -> TimeInterval {
        switch error {
        case .rateLimitExceeded(_, let retryAfter):
            return max(currentDelay, retryAfter ?? 0)
        default:
            return currentDelay
        }
    }

    private func fallbackModelIfNeeded(for error: EnhancementError) -> String? {
        guard aiService.selectedProvider == .openAI else {
            return nil
        }

        let currentModel = aiService.currentModel
        guard currentModel.lowercased().hasSuffix("-pro") else {
            return nil
        }

        switch error {
        case .rateLimitExceeded:
            return String(currentModel.dropLast(4))
        default:
            return nil
        }
    }

    private func recommendedOutputTokenLimit(for text: String, model: String) -> Int {
        let estimatedInputTokens = max(256, text.count / 4)
        let baseLimit = min(max(estimatedInputTokens, 768), 4096)

        if model.lowercased().hasSuffix("-pro") {
            return min(baseLimit, 2048)
        }

        return baseLimit
    }

    private func retryAfterInterval(from response: HTTPURLResponse) -> TimeInterval? {
        guard let rawValue = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        if let seconds = TimeInterval(rawValue), seconds > 0 {
            return seconds
        }

        return nil
    }

    private func rateLimitMessage(from data: Data, response: HTTPURLResponse) -> String? {
        let providerMessage = providerErrorMessage(from: data)

        if let retryAfter = retryAfterInterval(from: response), retryAfter > 0 {
            let seconds = Int(ceil(retryAfter))
            if let providerMessage, !providerMessage.isEmpty {
                return "\(providerMessage) Retry in about \(seconds) seconds."
            }
            return "Rate limit exceeded. Please try again in about \(seconds) seconds."
        }

        return providerMessage
    }

    private func providerErrorMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String,
               !message.isEmpty {
                return message
            }

            if let message = json["message"] as? String, !message.isEmpty {
                return message
            }
        }

        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw?.isEmpty == false ? raw : nil
    }
}
