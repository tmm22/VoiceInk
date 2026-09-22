import Foundation
import LLMkit
import SwiftData

/// ElevenLabs streaming provider wrapping `LLMkit.ElevenLabsStreamingClient`.
final class ElevenLabsStreamingProvider: LLMKitStreamingProvider<LLMkit.ElevenLabsStreamingClient> {
    init(modelContext: ModelContext) {
        super.init(
            client: LLMkit.ElevenLabsStreamingClient(), apiKeyProviderName: "ElevenLabs", modelContext: modelContext)
    }

    override func connectionParameters(model: any TranscriptionModel, language: String?) -> LLMKitStreamingConnection {
        LLMKitStreamingConnection(
            model: "scribe_v2_realtime", language: language, customVocabulary: customVocabularyTerms())
    }
}
