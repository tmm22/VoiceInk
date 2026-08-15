import Foundation

@MainActor
final class OpenAITranslationService: TextTranslationService {
    private let session: URLSession
    private let authorizationService: AuthorizationService
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let model = "gpt-4o-mini"

    init(
        session: URLSession = SecureURLSession.makeEphemeral(),
        keychain: KeychainManager = KeychainManager(),
        managedProvisioningClient: ManagedProvisioningClient? = nil,
        authorizationService: AuthorizationService? = nil
    ) {
        self.session = session
        let resolvedManagedProvisioningClient = managedProvisioningClient ?? .shared
        self.authorizationService = authorizationService ?? AuthorizationService(
            keychain: keychain,
            managedProvisioningClient: resolvedManagedProvisioningClient
        )
    }

    func hasCredentials() -> Bool {
        authorizationService.hasCredentials(for: "OpenAI")
    }

    func translate(text: String, targetLanguageCode: String) async throws -> TranslationResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let authorization = try await authorizationService.authorizationHeader(for: "OpenAI", headerType: .openAI)
        request.setValue(authorization.value, forHTTPHeaderField: authorization.header)
        request.timeoutInterval = 45

        let prompt = """
        You are a translation engine. Detect the language of the user's text and translate it into the language specified as TARGET. Respond only with JSON using the shape {"sourceLanguage":"<ISO 639-1>","translatedText":"<text>"}.
        TARGET: \(targetLanguageCode)
        TEXT: \(text)
        """

        let body = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: "You translate text and respond strictly with the requested JSON."),
                .init(role: "user", content: prompt)
            ],
            temperature: 0,
            responseFormat: .init(type: "json_object")
        )

        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)

            let responseData = try HTTPResponseHandler.handleResponse(
                response,
                data: data,
                onUnauthorized: {
                    if authorization.usedManagedCredential {
                        self.authorizationService.invalidateManagedCredential(for: .openAI)
                    }
                },
                clientErrorFormat: "Translation request failed (%d)",
                serverErrorFormat: "Translation service unavailable (%d)",
                unexpectedFormat: "Unexpected translation response: %d"
            )

            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: responseData)
            guard let content = decoded.choices.first?.message.content,
                  let payloadData = content.data(using: .utf8) else {
                throw TTSError.apiError("Translation response missing content")
            }

            let payload = try JSONDecoder().decode(TranslationPayload.self, from: payloadData)

            return TranslationResult(
                originalText: text,
                translatedText: payload.translatedText,
                detectedLanguageCode: payload.sourceLanguage.lowercased(),
                targetLanguageCode: targetLanguageCode.lowercased()
            )
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.networkError(error.localizedDescription)
        }
    }
}

private struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let responseFormat: ResponseFormat

    struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Codable {
        let type: String

        enum CodingKeys: String, CodingKey {
            case type
        }
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
    }
}

private struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        let message: ChatCompletionRequest.ChatMessage
    }

    let choices: [Choice]
}

private struct TranslationPayload: Codable {
    let sourceLanguage: String
    let translatedText: String
}
