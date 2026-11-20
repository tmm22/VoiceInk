import Foundation
import LLMkit
import SwiftData

final class XAIStreamingProvider: LLMKitStreamingProvider<LLMkit.XAIStreamingClient> {
    init(modelContext: ModelContext) {
        super.init(client: LLMkit.XAIStreamingClient(), apiKeyProviderName: "xAI", modelContext: modelContext)
    }
}
