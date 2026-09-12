import Foundation
import LLMkit

/// Mistral streaming provider wrapping `LLMkit.MistralStreamingClient`.
final class MistralStreamingProvider: LLMKitStreamingProvider<LLMkit.MistralStreamingClient> {
    init() {
        super.init(client: LLMkit.MistralStreamingClient(), apiKeyProviderName: "Mistral", modelContext: nil)
    }

    override func connectionParameters(model: any TranscriptionModel, language: String?) -> LLMKitStreamingConnection {
        LLMKitStreamingConnection(model: "voxtral-mini-transcribe-realtime-2602", language: language, customVocabulary: [])
    }
}
