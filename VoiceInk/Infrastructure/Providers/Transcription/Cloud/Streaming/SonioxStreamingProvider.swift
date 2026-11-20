import Foundation
import LLMkit
import SwiftData

/// Soniox streaming provider wrapping `LLMkit.SonioxStreamingClient`.
final class SonioxStreamingProvider: LLMKitStreamingProvider<LLMkit.SonioxStreamingClient> {
    private let finalization = AsyncStream<String>.makeStream()
    override var finalizationEvents: AsyncStream<String>? { finalization.stream }

    override func commit() async throws {
        let text = try await client.finalize()
        finalization.continuation.yield(text)
        finalization.continuation.finish()
    }

    deinit { finalization.continuation.finish() }

    init(modelContext: ModelContext) {
        super.init(client: LLMkit.SonioxStreamingClient(), apiKeyProviderName: "Soniox", modelContext: modelContext)
    }

    override var disconnectsClientOnConnectFailure: Bool { true }

    override var stopDisposition: StreamingStopDisposition {
        client.requiresFullRecording ? .useBatchFallback : .finalizeStreaming
    }

    override func connectionParameters(model: any TranscriptionModel, language: String?) -> LLMKitStreamingConnection {
        LLMKitStreamingConnection(model: "stt-rt-v6", language: language, customVocabulary: customVocabularyTerms())
    }
}
