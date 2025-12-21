import Foundation

// MARK: - URL Validation Errors
enum AIServiceURLError: LocalizedError {
    case invalidURL(String)
    case insecureURL(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let message):
            return "Invalid URL: \(message)"
        case .insecureURL(let message):
            return "Insecure URL: \(message)"
        }
    }
}

// MARK: - AI Provider Enum
enum AIProvider: String, CaseIterable {
    case cerebras = "Cerebras"
    case groq = "GROQ"
    case gemini = "Gemini"
    case anthropic = "Anthropic"
    case openAI = "OpenAI"
    case openRouter = "OpenRouter"
    case mistral = "Mistral"
    case elevenLabs = "ElevenLabs"
    case deepgram = "Deepgram"
    case soniox = "Soniox"
    case assemblyAI = "AssemblyAI"
    case zai = "ZAI"
    case ollama = "Ollama"
    case custom = "Custom"
    
    var baseURL: String {
        switch self {
        case .cerebras:
            return "https://api.cerebras.ai/v1/chat/completions"
        case .groq:
            return "https://api.groq.com/openai/v1/chat/completions"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .openAI:
            return "https://api.openai.com/v1/chat/completions"
        case .openRouter:
            return "https://openrouter.ai/api/v1/chat/completions"
        case .mistral:
            return "https://api.mistral.ai/v1/chat/completions"
        case .elevenLabs:
            return "https://api.elevenlabs.io/v1/speech-to-text"
        case .deepgram:
            return "https://api.deepgram.com/v1/listen"
        case .soniox:
            return "https://api.soniox.com/v1"
        case .assemblyAI:
            return "https://api.assemblyai.com/v2"
        case .zai:
            return "https://api.z.ai/api/paas/v4/chat/completions"
        case .ollama:
            // NOTE: Ollama runs locally, so http://localhost is acceptable for local development
            return UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        case .custom:
            return UserDefaults.standard.string(forKey: "customProviderBaseURL") ?? ""
        }
    }
    
    /// Validates that a custom URL is secure (HTTPS) for use with API credentials.
    /// - Parameter urlString: The URL string to validate
    /// - Returns: A validated URL
    /// - Throws: AIServiceURLError if the URL is invalid or insecure
    /// - Note: Ollama URLs are exempt from HTTPS requirement as they typically run locally
    static func validateSecureURL(_ urlString: String, allowLocalhost: Bool = false) throws -> URL {
        guard let url = URL(string: urlString) else {
            throw AIServiceURLError.invalidURL("Cannot parse URL: \(urlString)")
        }
        
        guard let host = url.host, !host.isEmpty else {
            throw AIServiceURLError.invalidURL("Missing host in URL")
        }
        
        // Allow localhost/127.0.0.1 for local development (e.g., Ollama)
        let isLocalhost = host == "localhost" || host == "127.0.0.1" || host == "::1"
        if allowLocalhost && isLocalhost {
            return url
        }
        
        // CRITICAL: Enforce HTTPS for any URL carrying API credentials
        guard url.scheme?.lowercased() == "https" else {
            throw AIServiceURLError.insecureURL("HTTPS required for API endpoints. Use https:// instead of http://")
        }
        
        return url
    }
    
    var defaultModel: String {
        switch self {
        case .cerebras:
            return "gpt-oss-120b"
        case .groq:
            return "openai/gpt-oss-120b"
        case .gemini:
            return "gemini-3-flash-preview"
        case .anthropic:
            return "claude-sonnet-4-5"
        case .openAI:
            return "gpt-5.2"
        case .mistral:
            return "mistral-large-latest"
        case .elevenLabs:
            return "scribe_v2_realtime"
        case .deepgram:
            return "whisper-1"
        case .soniox:
            return "stt-async-v3"
        case .assemblyAI:
            return "best"
        case .zai:
            return "glm-4.5-flash"
        case .ollama:
            return UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "mistral"
        case .custom:
            return UserDefaults.standard.string(forKey: "customProviderModel") ?? ""
        case .openRouter:
            return "openai/gpt-oss-120b"
        }
    }
    
    var availableModels: [String] {
        switch self {
        case .cerebras:
            return [
                "gpt-oss-120b",
                "llama-3.1-8b",
                "llama-4-scout-17b-16e-instruct",
                "llama-3.3-70b",
                "qwen-3-32b",
                "qwen-3-235b-a22b-instruct-2507"
            ]
        case .groq:
            return [
                "llama-3.1-8b-instant",
                "llama-3.3-70b-versatile",
                "moonshotai/kimi-k2-instruct-0905",
                "qwen/qwen3-32b",
                "meta-llama/llama-4-maverick-17b-128e-instruct",
                "openai/gpt-oss-120b",
                "openai/gpt-oss-20b"
            ]
        case .gemini:
            return [
                "gemini-3-pro-preview",
                "gemini-3-flash-preview"
            ]
        case .anthropic:
            return [
                "claude-opus-4-5",
                "claude-sonnet-4-5",
                "claude-haiku-4-5"
            ]
        case .openAI:
            return [
                "gpt-5.2",
                "gpt-5.2-pro",
                "gpt-5.1",
                "gpt-5-mini",
                "gpt-5-nano",
                "gpt-4.1",
                "gpt-4.1-mini"
            ]
        case .mistral:
            return [
                "mistral-large-latest",
                "mistral-medium-latest",
                "mistral-small-latest",
                "mistral-saba-latest"
            ]
        case .elevenLabs:
            return ["scribe_v2_realtime", "scribe_v1", "scribe_v1_experimental"]
        case .deepgram:
            return ["whisper-1"]
        case .soniox:
            return ["stt-async-v3"]
        case .assemblyAI:
            return ["best", "nano"]
        case .zai:
            return [
                "glm-4.5-flash",        // Free tier
                "glm-4.6",              // Latest flagship, 200K context
                "glm-4.5",              // Previous flagship
                "glm-4.5-air",          // Lightweight/faster
                "glm-4-32b-0414-128k"   // Open weights model
            ]
        case .ollama:
            return []
        case .custom:
            return []
        case .openRouter:
            return []
        }
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .ollama:
            return false
        default:
            return true
        }
    }
}
