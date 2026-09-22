import Foundation
import LLMkit
import SwiftData
import os

/// Parameters handed to an LLMkit streaming client's `connect`.
struct LLMKitStreamingConnection {
    var model: String
    var language: String?
    var customVocabulary: [String]
}

/// Shared plumbing for cloud streaming providers built on an LLMkit streaming client.
///
/// Owns the event continuation, the client→app event forwarding task, the API-key lookup, the
/// custom-vocabulary fetch and the `LLMKitError` → `StreamingTranscriptionError` mapping. Concrete
/// providers subclass this and override only the vendor-specific hooks.
class LLMKitStreamingProvider<Client: LLMkit.StreamingTranscriptionProvider>: StreamingTranscriptionProvider {
    let client: Client
    let modelContext: ModelContext?
    /// Provider name used with `APIKeyManager`.
    let apiKeyProviderName: String
    let logger: Logger

    private let apiKeyLookup: (String) -> String?
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?
    private var forwardingTask: Task<Void, Never>?
    /// Vocabulary fetched on the main actor for the connection in progress.
    private var connectionVocabulary: [String] = []

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    init(
        client: Client, apiKeyProviderName: String, modelContext: ModelContext?,
        apiKeyLookup: @escaping (String) -> String? = { APIKeyManager.shared.getAPIKey(forProvider: $0) }
    ) {
        self.apiKeyLookup = apiKeyLookup
        self.client = client
        self.apiKeyProviderName = apiKeyProviderName
        self.modelContext = modelContext
        self.logger = Logger(subsystem: AppLogger.subsystem, category: "\(apiKeyProviderName)Streaming")
        let (stream, continuation) = AsyncStream<StreamingTranscriptionEvent>.makeStream()
        transcriptionEvents = stream
        eventsContinuation = continuation
    }

    deinit {
        forwardingTask?.cancel()
        eventsContinuation?.finish()
        // Some clients retain their own receive task until explicitly disconnected.
        // Capture only the client: cleanup must not extend this provider's lifetime.
        let client = client
        Task { await client.disconnect() }
    }

    // MARK: - Vendor hooks

    /// Translates the selected model and language into the client's connect parameters.
    /// The default passes the model name and language through and attaches the custom vocabulary.
    func connectionParameters(model: any TranscriptionModel, language: String?) -> LLMKitStreamingConnection {
        LLMKitStreamingConnection(model: model.name, language: language, customVocabulary: customVocabularyTerms())
    }

    /// Upper bound on custom vocabulary terms sent to the vendor; `nil` means no limit.
    var vocabularyLimit: Int? { nil }

    /// Whether `connectionParameters` sends dictionary terms. Providers that never send them skip the fetch.
    var sendsCustomVocabulary: Bool { true }

    /// Whether the client should be torn down when `connect` fails.
    var disconnectsClientOnConnectFailure: Bool { false }

    /// Whether the app-facing event stream ends as soon as the client's event stream ends.
    var finishesEventsWhenClientStreamEnds: Bool { false }

    /// Called at the start of `connect`, before event forwarding starts.
    func willConnect() {}

    /// Called at the start of `commit`, before the client is asked to finalize.
    func willCommit() {}

    /// Called on the forwarding task when the client's event stream ends. Use `yield(_:)` to emit
    /// trailing events before the stream is finished.
    func clientEventStreamDidEnd() {}

    var stopDisposition: StreamingStopDisposition { .finalizeStreaming }

    var finalizationEvents: AsyncStream<String>? { nil }

    // MARK: - StreamingTranscriptionProvider

    final func connect(model: any TranscriptionModel, language: String?) async throws {
        guard let apiKey = apiKeyLookup(apiKeyProviderName), !apiKey.isEmpty else {
            throw StreamingTranscriptionError.missingAPIKey
        }

        // The dictionary lives in the main context; SwiftData contexts must stay on their actor.
        connectionVocabulary =
            sendsCustomVocabulary
            ? await DictionaryVocabulary.terms(from: modelContext, limit: vocabularyLimit, logger: logger)
            : []
        let parameters = connectionParameters(model: model, language: language)

        // Cancel any existing forwarding task before starting a new one.
        forwardingTask?.cancel()
        willConnect()
        startEventForwarding()

        do {
            try await client.connect(
                apiKey: apiKey,
                model: parameters.model,
                language: parameters.language,
                customVocabulary: parameters.customVocabulary
            )
        } catch {
            forwardingTask?.cancel()
            forwardingTask = nil
            if disconnectsClientOnConnectFailure {
                await client.disconnect()
            }
            // Cancelling forwarding no longer runs the end-of-stream hook, so end the app-facing
            // stream explicitly for providers whose stream ends with the client's (Cartesia).
            if finishesEventsWhenClientStreamEnds {
                eventsContinuation?.finish()
            }
            throw Self.mapError(error)
        }
    }

    final func sendAudioChunk(_ data: Data) async throws {
        do {
            try await client.sendAudioChunk(data)
        } catch {
            throw Self.mapError(error)
        }
    }

    final func commit() async throws {
        willCommit()
        do {
            try await client.commit()
        } catch {
            throw Self.mapError(error)
        }
    }

    final func disconnect() async {
        forwardingTask?.cancel()
        forwardingTask = nil
        await client.disconnect()
        eventsContinuation?.finish()
    }

    // MARK: - Shared helpers

    /// Emits an event on the app-facing stream.
    final func yield(_ event: StreamingTranscriptionEvent) {
        eventsContinuation?.yield(event)
    }

    private func startEventForwarding() {
        // Hold the stream, never the provider, across the unbounded next-event await.
        let stream = client.transcriptionEvents
        forwardingTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled, let self else { return }
                switch event {
                case .sessionStarted:
                    self.yield(.sessionStarted)
                case .partial(let text):
                    self.yield(.partial(text: text))
                case .committed(let text):
                    self.yield(.committed(text: text))
                case .error(let message):
                    self.yield(.error(StreamingTranscriptionError.serverError(message)))
                }
            }
            // Cancellation is not a vendor finalization acknowledgement. In particular,
            // it must not synthesize Cartesia's successful empty committed event.
            guard !Task.isCancelled, let self else { return }
            if self.finishesEventsWhenClientStreamEnds {
                self.clientEventStreamDidEnd()
                self.eventsContinuation?.finish()
            }
        }
    }

    /// Unique, trimmed custom vocabulary terms for the current connection, capped at `vocabularyLimit`.
    /// Fetched on the main actor at the start of `connect`; vendor hooks read the prepared list.
    final func customVocabularyTerms() -> [String] {
        connectionVocabulary
    }

    static func mapError(_ error: Error) -> Error {
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

enum DictionaryVocabulary {
    /// Unique, trimmed dictionary terms, capped at `vocabularyLimit`. Runs on the main actor because
    /// the dictionary's `ModelContext` is the app's main context.
    @MainActor
    static func terms(from modelContext: ModelContext?, limit vocabularyLimit: Int?, logger: Logger) -> [String] {
        guard let modelContext else { return [] }

        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\.word)])
        let vocabularyWords: [VocabularyWord]
        do {
            vocabularyWords = try modelContext.fetch(descriptor)
        } catch {
            // Recoverable: stream without custom vocabulary, but leave a diagnostic trail.
            logger.error(
                "Failed to fetch custom vocabulary; continuing without it: \(AppLogger.errorMetadata(error), privacy: .public)"
            )
            return []
        }

        var seen = Set<String>()
        var unique: [String] = []
        for word in vocabularyWords {
            let trimmed = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard seen.insert(trimmed.lowercased()).inserted else { continue }
            unique.append(trimmed)
            if let vocabularyLimit, unique.count == vocabularyLimit { break }
        }
        return unique
    }
}
