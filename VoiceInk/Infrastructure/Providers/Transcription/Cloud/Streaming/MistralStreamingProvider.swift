import Foundation
import LLMkit
import SwiftData

final class MistralStreamingProvider: LLMKitStreamingProvider<LLMkit.MistralStreamingClient> {
    init(modelContext: ModelContext) {
        super.init(client: LLMkit.MistralStreamingClient(), apiKeyProviderName: "Mistral", modelContext: modelContext)
    }
}
