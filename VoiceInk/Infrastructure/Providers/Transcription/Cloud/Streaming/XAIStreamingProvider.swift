import Foundation
import LLMkit

/// xAI streaming provider wrapping `LLMkit.XAIStreamingClient`.
final class XAIStreamingProvider: LLMKitStreamingProvider<LLMkit.XAIStreamingClient> {
    init() {
        super.init(client: LLMkit.XAIStreamingClient(), apiKeyProviderName: "xAI", modelContext: nil)
    }

    override func connectionParameters(model: any TranscriptionModel, language: String?) -> LLMKitStreamingConnection {
        LLMKitStreamingConnection(model: model.name, language: language, customVocabulary: [])
    }
}
