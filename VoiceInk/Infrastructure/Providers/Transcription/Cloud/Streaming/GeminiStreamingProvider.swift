import Foundation
import LLMkit
import SwiftData
import os

/// Gemini streaming provider wrapping `LLMkit.GeminiStreamingClient`.
final class GeminiStreamingProvider: StreamingTranscriptionProvider {
    private let client = LLMkit.GeminiStreamingClient()
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: AppLogger.subsystem, category: "GeminiStreaming")
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private var forwardingTask: Task<Void, Never>?

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>
    var finalizationEvents: AsyncStream<String>? { client.finalizationEvents }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        forwardingTask?.cancel()
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: "Gemini"), !apiKey.isEmpty else {
            throw StreamingTranscriptionError.missingAPIKey
        }

        forwardingTask?.cancel()
        startEventForwarding()

        do {
            try await client.connect(
                apiKey: apiKey,
                model: model.name,
                language: language,
                customVocabulary: customVocabularyTerms()
            )
        } catch {
            forwardingTask?.cancel()
            forwardingTask = nil
            await client.disconnect()
            throw mapError(error)
        }
    }

    func sendAudioChunk(_ data: Data) async throws {
        do {
            try await client.sendAudioChunk(data)
        } catch {
            throw mapError(error)
        }
    }

    func commit() async throws {
        do {
            try await client.commit()
        } catch {
            throw mapError(error)
        }
    }

    func disconnect() async {
        forwardingTask?.cancel()
        forwardingTask = nil
        await client.disconnect()
        eventsContinuation?.finish()
    }

    private func startEventForwarding() {
        forwardingTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.client.transcriptionEvents {
                switch event {
                case .sessionStarted:
                    self.eventsContinuation?.yield(.sessionStarted)
                case .partial(let text):
                    self.eventsContinuation?.yield(.partial(text: text))
                case .committed(let text):
                    self.eventsContinuation?.yield(.committed(text: text))
                case .error(let message):
                    self.eventsContinuation?.yield(.error(StreamingTranscriptionError.serverError(message)))
                }
            }
        }
    }

    private func customVocabularyTerms() -> [String] {
        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\.word)])
        let vocabularyWords: [VocabularyWord]
        do {
            vocabularyWords = try modelContext.fetch(descriptor)
        } catch {
            // Recoverable: stream without custom vocabulary, but leave a diagnostic trail.
            logger.error(
                "Failed to fetch custom vocabulary for Gemini streaming; continuing without it: \(AppLogger.errorMetadata(error), privacy: .public)"
            )
            return []
        }

        var seen = Set<String>()
        var unique: [String] = []
        for word in vocabularyWords {
            let trimmed = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            unique.append(trimmed)
            if unique.count == 1_000 { break }
        }
        return unique
    }

    private func mapError(_ error: Error) -> Error {
        guard let llmError = error as? LLMKitError else { return error }
        switch llmError {
        case .missingAPIKey:
            return StreamingTranscriptionError.missingAPIKey
        case .httpError(_, let message):
            return StreamingTranscriptionError.serverError(message)
        case .networkError(let detail):
            return StreamingTranscriptionError.connectionFailed(detail)
        case .timeout:
            return StreamingTranscriptionError.timeout
        default:
            return StreamingTranscriptionError.serverError(llmError.localizedDescription)
        }
    }
}
