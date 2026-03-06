import Foundation

extension AIProvider {
    var apiKeyURL: URL? {
        switch self {
        case .groq:
            return URL(string: "https://console.groq.com/keys")
        case .openAI:
            return URL(string: "https://platform.openai.com/api-keys")
        case .gemini:
            return URL(string: "https://makersuite.google.com/app/apikey")
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/keys")
        case .mistral:
            return URL(string: "https://console.mistral.ai/api-keys")
        case .elevenLabs:
            return URL(string: "https://elevenlabs.io/speech-synthesis")
        case .deepgram:
            return URL(string: "https://console.deepgram.com/api-keys")
        case .soniox:
            return URL(string: "https://console.soniox.com/")
        case .assemblyAI:
            return URL(string: "https://www.assemblyai.com/app/api-keys")
        case .openRouter:
            return URL(string: "https://openrouter.ai/keys")
        case .cerebras:
            return URL(string: "https://cloud.cerebras.ai/")
        case .zai:
            return URL(string: "https://z.ai/manage-apikey/apikey-list")
        case .ollama, .custom:
            return nil
        }
    }

    var billingLabel: String {
        switch self {
        case .groq, .gemini, .cerebras, .zai:
            return "Free"
        default:
            return "Paid"
        }
    }
}
