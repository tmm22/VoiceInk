import Foundation
import LLMkit
import SwiftData

/// Deepgram streaming provider wrapping `LLMkit.DeepgramStreamingClient`.
final class DeepgramStreamingProvider: LLMKitStreamingProvider<LLMkit.DeepgramStreamingClient> {
    init(modelContext: ModelContext) {
        super.init(client: LLMkit.DeepgramStreamingClient(), apiKeyProviderName: "Deepgram", modelContext: modelContext)
    }

    override var finalizationEvents: AsyncStream<String>? { client.finalizationEvents }

    override var vocabularyLimit: Int? { 100 }

    override func connectionParameters(model: any TranscriptionModel, language: String?) -> LLMKitStreamingConnection {
        // nova-3 auto-detects across languages with the "multi" code.
        let deepgramLanguage = model.name == "nova-3" && (language == nil || language == "auto") ? "multi" : language
        return LLMKitStreamingConnection(
            model: model.name, language: deepgramLanguage, customVocabulary: customVocabularyTerms())
    }
}
