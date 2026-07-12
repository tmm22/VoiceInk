import Foundation

/// Reasoning effort levels supported by AI models
enum ReasoningEffort: String, CaseIterable, Codable {
    case none = "none"
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
    
    var description: String {
        switch self {
        case .none: return "No reasoning - fastest responses"
        case .low: return "Light reasoning - balanced speed and quality"
        case .medium: return "Moderate reasoning - better quality"
        case .high: return "Deep reasoning - highest quality, slower"
        }
    }
}

struct ReasoningConfig {
    static let geminiReasoningModels: Set<String> = [
        "gemini-3.1-pro-preview",
        "gemini-3-pro-preview",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite"
    ]

    static let openAIReasoningModels: Set<String> = [
        "gpt-5.6",
        "gpt-5.6-terra",
        "gpt-5.6-luna",
        "gpt-5.5",
        "gpt-5.5-pro",
        "gpt-5.4",
        "gpt-5.4-pro",
        "gpt-5.4-mini",
        "gpt-5.4-nano",
        "gpt-5-mini",
        "gpt-5-nano",
        "gpt-5.1"
    ]

    static let cerebrasReasoningModels: Set<String> = [
        "gpt-oss-120b"
    ]
    
    /// All models that support reasoning effort parameter
    static var allReasoningModels: Set<String> {
        geminiReasoningModels.union(openAIReasoningModels).union(cerebrasReasoningModels)
    }
    
    /// Checks if a model supports reasoning effort parameter
    static func supportsReasoning(_ modelName: String) -> Bool {
        allReasoningModels.contains(modelName)
    }

    /// Returns the reasoning parameter for a model, using user preference if provided
    /// - Parameters:
    ///   - modelName: The name of the AI model
    ///   - userPreference: Optional user-selected reasoning effort level
    /// - Returns: The reasoning effort string to send to the API, or nil if model doesn't support it
    static func getReasoningParameter(for modelName: String, userPreference: ReasoningEffort? = nil) -> String? {
        guard supportsReasoning(modelName) else {
            return nil
        }

        return normalizedEffort(for: modelName, userPreference: userPreference).rawValue
    }

    private static func normalizedEffort(for modelName: String, userPreference: ReasoningEffort?) -> ReasoningEffort {
        let effort = userPreference ?? .low
        let modelLower = modelName.lowercased()

        if modelLower == "gpt-5-pro" {
            return .high
        }

        if modelLower.hasPrefix("gpt-5.") && modelLower.hasSuffix("-pro") {
            return effort == .high ? .high : .medium
        }

        return effort
    }
}
