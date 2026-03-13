import Foundation

@MainActor
protocol TranscriptCleanupServicing {
    func clean(transcript: String, instruction: String, label: String?) async throws -> TranscriptCleanupResult
}

@MainActor
final class TranscriptCleanupService: TranscriptCleanupServicing {
    private let session: URLSession
    private let authorizationService: AuthorizationService
    // Force unwrap safe: hardcoded valid URL
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

    func clean(transcript: String, instruction: String, label: String?) async throws -> TranscriptCleanupResult {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstruction.isEmpty else {
            throw TTSError.apiError("Cleanup instruction cannot be empty")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let authorization = try await authorizationService.authorizationHeader(for: "OpenAI", headerType: .openAI)
        request.setValue(authorization.value, forHTTPHeaderField: authorization.header)
        request.timeoutInterval = 45

        let body = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: Self.cleanupSystemPrompt),
                .init(role: "user", content: Self.cleanupUserPrompt(instruction: trimmedInstruction, transcript: transcript))
            ],
            temperature: 0.3
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
                clientErrorFormat: "Cleanup request failed (%d)",
                serverErrorFormat: "Cleanup service unavailable (%d)",
                unexpectedFormat: "Unexpected response: %d"
            )

            let payload = try JSONDecoder().decode(ChatCompletionResponse.self, from: responseData)
            guard let output = payload.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else {
                throw TTSError.apiError("Cleanup response missing content")
            }
            return TranscriptCleanupResult(instruction: trimmedInstruction, label: label, output: output)
        } catch let error as TTSError {
            throw error
        } catch {
            throw TTSError.networkError(error.localizedDescription)
        }
    }
}

private extension TranscriptCleanupService {
    struct ChatCompletionRequest: Codable {
        struct Message: Codable {
            let role: String
            let content: String
        }

        struct ResponseFormat: Codable {
            let type: String
        }

        let model: String
        let messages: [Message]
        let temperature: Double

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
        }
    }

    struct ChatCompletionResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let role: String
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    static let cleanupSystemPrompt = "You rewrite transcripts according to the provided instructions. Return the cleaned transcript only, ready for narration."

    static func cleanupUserPrompt(instruction: String, transcript: String) -> String {
        "Instruction:\n\(instruction)\n\nTranscript:\n\(transcript)"
    }
}
