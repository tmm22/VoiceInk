import Foundation

struct TokenBudget {
    let provider: String
    let model: String
    
    var maxInputTokens: Int {
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
            return 8_000
        } else {
            return 8_000
        }
    }
    
    var availableForContext: Int {
        return max(1000, maxInputTokens - 4000)
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
        // Sort sections: Priority 1 (High) -> Priority 5 (Low)
        let sortedSections = sections.sorted { section1, section2 in
            let p1 = getPriority(section1, map: priorities)
            let p2 = getPriority(section2, map: priorities)
            return p1 < p2
        }
        
        var finalSections: [ContextSection] = []
        var budgetRemaining = budget
        
        for section in sortedSections {
            let estimatedCost = estimateTokens(section.content)
            
            if budgetRemaining >= estimatedCost {
                // Fits entirely
                finalSections.append(section)
                budgetRemaining -= estimatedCost
            } else if budgetRemaining > 50 { // Only include if we can fit at least ~200 chars
                // Needs truncation
                let allowedChars = budgetRemaining * 4
                let truncatedContent = smartTruncate(section.content, maxLength: allowedChars)
                
                finalSections.append(ContextSection(
                    content: truncatedContent + "\n...[TRUNCATED]",
                    source: section.source,
                    capturedAt: section.capturedAt,
                    characterCount: truncatedContent.count,
                    wasTruncated: true
                ))
                budgetRemaining = 0
            } else {
                // Skip entirely
                continue 
            }
        }
        
        return finalSections
    }
    
    private func getPriority(_ section: ContextSection, map: [ContextType: Int]) -> Int {
        if let type = ContextType(rawValue: section.source) {
            return map[type] ?? 100
        }
        return 100
    }
    
    /// Truncates text at the nearest semantic boundary (paragraph, sentence, word)
    private func smartTruncate(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength { return text }
        
        let targetEndIndex = text.index(text.startIndex, offsetBy: maxLength)
        let slice = text[..<targetEndIndex]
        
        // 1. Try cutting at last paragraph (double newline)
        if let lastParagraph = slice.range(of: "\n\n", options: .backwards) {
            return String(text[..<lastParagraph.lowerBound])
        }
        
        // 2. Try cutting at last newline
        if let lastNewline = slice.range(of: "\n", options: .backwards) {
            return String(text[..<lastNewline.lowerBound])
        }
        
        // 3. Try cutting at last sentence (. )
        if let lastSentence = slice.range(of: ". ", options: .backwards) {
            return String(text[..<lastSentence.upperBound])
        }
        
        // 4. Fallback: Cut at last space to avoid splitting words
        if let lastSpace = slice.range(of: " ", options: .backwards) {
            return String(text[..<lastSpace.lowerBound])
        }
        
        // 5. Hard limit
        return String(slice)
    }
}
