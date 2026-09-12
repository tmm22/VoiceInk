import Foundation
import LLMkit
import SwiftData

/// Speechmatics streaming provider wrapping `LLMkit.SpeechmaticsStreamingClient`.
final class SpeechmaticsStreamingProvider: LLMKitStreamingProvider<LLMkit.SpeechmaticsStreamingClient> {
    init(modelContext: ModelContext) {
        super.init(
            client: LLMkit.SpeechmaticsStreamingClient(), apiKeyProviderName: "Speechmatics", modelContext: modelContext)
    }

    override func connectionParameters(model: any TranscriptionModel, language: String?) -> LLMKitStreamingConnection {
        let operatingPoint = model.name.contains("standard") ? "standard" : "enhanced"
        return LLMKitStreamingConnection(
            model: operatingPoint, language: language, customVocabulary: customVocabularyTerms())
    }
}
