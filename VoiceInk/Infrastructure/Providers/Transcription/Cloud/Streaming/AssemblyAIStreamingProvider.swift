import Foundation
import LLMkit
import SwiftData

/// AssemblyAI streaming provider wrapping `LLMkit.AssemblyAIStreamingClient`.
final class AssemblyAIStreamingProvider: LLMKitStreamingProvider<LLMkit.AssemblyAIStreamingClient> {
    init(modelContext: ModelContext) {
        super.init(
            client: LLMkit.AssemblyAIStreamingClient(), apiKeyProviderName: "AssemblyAI", modelContext: modelContext)
    }
}
