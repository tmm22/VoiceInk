import Foundation
import LLMkit
import SwiftData

/// Gemini streaming provider wrapping `LLMkit.GeminiStreamingClient`.
final class GeminiStreamingProvider: LLMKitStreamingProvider<LLMkit.GeminiStreamingClient> {
    init(modelContext: ModelContext) {
        super.init(client: LLMkit.GeminiStreamingClient(), apiKeyProviderName: "Gemini", modelContext: modelContext)
    }

    override var finalizationEvents: AsyncStream<String>? { client.finalizationEvents }

    override var vocabularyLimit: Int? { 1_000 }

    override var disconnectsClientOnConnectFailure: Bool { true }
}
