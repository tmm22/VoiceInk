import Foundation
import LLMkit
import SwiftData

/// Soniox streaming provider wrapping `LLMkit.SonioxStreamingClient`.
final class SonioxStreamingProvider: LLMKitStreamingProvider<LLMkit.SonioxStreamingClient> {
    init(modelContext: ModelContext) {
        super.init(client: LLMkit.SonioxStreamingClient(), apiKeyProviderName: "Soniox", modelContext: modelContext)
    }

    override func connectionParameters(model: any TranscriptionModel, language: String?) -> LLMKitStreamingConnection {
        LLMKitStreamingConnection(model: "stt-rt-v5", language: language, customVocabulary: customVocabularyTerms())
    }
}
