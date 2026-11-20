import Foundation
import LLMkit
import SwiftData

/// AssemblyAI streaming provider wrapping `LLMkit.AssemblyAIStreamingClient`.
final class AssemblyAIStreamingProvider: LLMKitStreamingProvider<LLMkit.AssemblyAIStreamingClient> {
    override var finalizationEvents: AsyncStream<String>? { client.finalizationEvents }

    init(modelContext: ModelContext) {
        super.init(
            client: LLMkit.AssemblyAIStreamingClient(), apiKeyProviderName: "AssemblyAI", modelContext: modelContext)
    }
}
