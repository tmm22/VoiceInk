import Foundation

/// Enum representing the type of enhancement prompt
enum EnhancementPrompt {
    case transcriptionEnhancement
    case aiAssistant
}

/// Errors that can occur during AI enhancement
enum EnhancementError: Error {
    /// AI provider is not configured (missing API key)
    case notConfigured
    
    /// Response from AI provider was invalid or malformed
    case invalidResponse
    
    /// AI enhancement failed to process the text
    case enhancementFailed
    
    /// Network connection failed
    case networkError
    
    /// Server encountered an error (5xx status codes)
    case serverError
    
    /// Rate limit exceeded (429 status code)
    case rateLimitExceeded(message: String?, retryAfter: TimeInterval?)
    
    /// Custom error with a specific message
    case customError(String)
}

// MARK: - LocalizedError Conformance
extension EnhancementError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI provider not configured. Please check your API key."
        case .invalidResponse:
            return "Invalid response from AI provider."
        case .enhancementFailed:
            return "AI enhancement failed to process the text."
        case .networkError:
            return "Network connection failed. Check your internet."
        case .serverError:
            return "The AI provider's server encountered an error. Please try again later."
        case .rateLimitExceeded(let message, let retryAfter):
            if let message, !message.isEmpty {
                return message
            }
            if let retryAfter, retryAfter > 0 {
                let seconds = Int(ceil(retryAfter))
                return "Rate limit exceeded. Please try again in about \(seconds) seconds."
            }
            return "Rate limit exceeded. Please try again later."
        case .customError(let message):
            return message
        }
    }
}
