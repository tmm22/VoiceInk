import Foundation
import LLMkit
import SwiftData

/// ElevenLabs streaming provider wrapping `LLMkit.ElevenLabsStreamingClient`.
final class ElevenLabsStreamingProvider: LLMKitStreamingProvider<LLMkit.ElevenLabsStreamingClient> {
    private let finalization = AsyncStream<String>.makeStream()
    override var finalizationEvents: AsyncStream<String>? { finalization.stream }

    override func commit() async throws {
        let text = try await client.finalize()
        finalization.continuation.yield(text)
        finalization.continuation.finish()
    }

    deinit { finalization.continuation.finish() }

    init(modelContext: ModelContext) {
        super.init(
            client: LLMkit.ElevenLabsStreamingClient(), apiKeyProviderName: "ElevenLabs", modelContext: modelContext)
    }

    override func connectionParameters(model: any TranscriptionModel, language: String?) throws -> LLMKitStreamingConnection {
        guard let streamingID = ElevenLabsProvider.ScribeModel(rawValue: model.name)?.streamingID else {
            throw CloudTranscriptionError.unsupportedModel(model.name)
        }
        return LLMKitStreamingConnection(
            model: streamingID, language: language, customVocabulary: customVocabularyTerms())
    }
}
