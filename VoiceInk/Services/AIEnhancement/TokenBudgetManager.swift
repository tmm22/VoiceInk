import Foundation

struct TokenBudget {
    let provider: String  // Using String to avoid circular dependency if AIProvider isn't available
    let model: String
    
    var maxInputTokens: Int {
        // Provider-specific limits (approximations)
        let providerLower = provider.lowercased()
        let modelLower = model.lowercased()
        
        if providerLower.contains("openai") {
            if modelLower.contains("gpt-4-turbo") || modelLower.contains("gpt-4o") { return 128_000 }
            if modelLower.contains("gpt-4") { return 8_000 }
            if modelLower.contains("gpt-3.5") { return 16_000 }
            return 8_000
        } else if providerLower.contains("anthropic") {
            return 200_000
        } else if providerLower.contains("ollama") {
            return 8_000  // Conservative default for local models
        } else {
            return 8_000
        }
    }
    
    // Reserve tokens for system prompt and response
    var availableForContext: Int {
        return max(1000, maxInputTokens - 4000)  // Ensure at least 1000 tokens, reserve 4k
    }
}

class TokenBudgetManager {
    /// Estimates token count (4 chars ≈ 1 token)
    func estimateTokens(_ text: String) -> Int {
        return text.count / 4
    }
    
    /// Truncates context sections to fit budget, respecting priorities
    func fitToBudget(
        sections: [ContextSection],
        priorities: [ContextType: Int],
        budget: Int
    ) -> [ContextSection] {
        var currentTokens = sections.reduce(0) { $0 + estimateTokens($1.content) }
        
        if currentTokens <= budget {
            return sections
        }
        
        // Sort sections by priority (higher int value = lower priority, so we truncate those first)
        // Priorities map: lower Int = higher priority.
        // We want to truncate lower priority items first (higher Int value).
        
        var mutableSections = sections
        
        // Helper to get priority
        func getPriority(_ section: ContextSection) -> Int {
            // Map section source string to ContextType to get priority
            // This requires the source string to match ContextType raw values or similar
            // For now, default to medium priority if unknown
            if let type = ContextType(rawValue: section.source) {
                return priorities[type] ?? 100
            }
            return 100
        }
        
        // Sort by priority descending (highest number = lowest priority = first to truncate)
        mutableSections.sort { getPriority($0) > getPriority($1) }
        
        var finalSections: [ContextSection] = []
        var budgetRemaining = budget
        
        // Iterate through sorted sections (lowest priority first)
        // Actually, wait. We want to KEEP high priority items.
        // If we process from High Priority to Low Priority, we fill the budget with High Priority stuff first.
        
        mutableSections.sort { getPriority($0) < getPriority($1) } // Ascending: 1, 2, 3... (High to Low priority)
        
        for section in mutableSections {
            let tokens = estimateTokens(section.content)
            if budgetRemaining >= tokens {
                finalSections.append(section)
                budgetRemaining -= tokens
            } else if budgetRemaining > 100 {
                // Truncate if we have some budget left
                let allowedChars = budgetRemaining * 4
                let truncatedContent = String(section.content.prefix(allowedChars)) + "\n...[TRUNCATED]"
                
                finalSections.append(ContextSection(
                    content: truncatedContent,
                    source: section.source,
                    capturedAt: section.capturedAt,
                    characterCount: truncatedContent.count,
                    wasTruncated: true
                ))
                budgetRemaining = 0
            } else {
                // Skip entirely if not enough budget
                continue 
            }
        }
        
        return finalSections
    }
}
