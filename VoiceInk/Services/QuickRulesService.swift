import Foundation

/// Quick text correction rule
struct QuickRule: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var pattern: String
    var replacement: String
    var isRegex: Bool
    var isEnabled: Bool
    var category: RuleCategory
    
    enum RuleCategory: String, Codable, CaseIterable {
        case casualToFormal = "Casual to Formal"
        case fillerWords = "Filler Words"
        case duplicates = "Duplicates"
        case spacing = "Spacing"
        case punctuation = "Punctuation"
        case custom = "Custom"
        
        var icon: String {
            switch self {
            case .casualToFormal: return "text.badge.checkmark"
            case .fillerWords: return "text.badge.minus"
            case .duplicates: return "doc.on.doc"
            case .spacing: return "space"
            case .punctuation: return "quote.opening"
            case .custom: return "hammer"
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        pattern: String,
        replacement: String,
        isRegex: Bool,
        isEnabled: Bool = true,
        category: RuleCategory
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.pattern = pattern
        self.replacement = replacement
        self.isRegex = isRegex
        self.isEnabled = isEnabled
        self.category = category
    }
}

/// Service for managing and applying quick text correction rules
class QuickRulesService {
    static let shared = QuickRulesService()
    
    private init() {}
    
    /// Default preset rules
    static let defaultRules: [QuickRule] = [
        // Casual to Formal
        QuickRule(
            name: "gonna → going to",
            description: "Replace 'gonna' with 'going to'",
            pattern: "\\bgonna\\b",
            replacement: "going to",
            isRegex: true,
            category: .casualToFormal
        ),
        QuickRule(
            name: "wanna → want to",
            description: "Replace 'wanna' with 'want to'",
            pattern: "\\bwanna\\b",
            replacement: "want to",
            isRegex: true,
            category: .casualToFormal
        ),
        QuickRule(
            name: "kinda → kind of",
            description: "Replace 'kinda' with 'kind of'",
            pattern: "\\bkinda\\b",
            replacement: "kind of",
            isRegex: true,
            category: .casualToFormal
        ),
        QuickRule(
            name: "sorta → sort of",
            description: "Replace 'sorta' with 'sort of'",
            pattern: "\\bsorta\\b",
            replacement: "sort of",
            isRegex: true,
            category: .casualToFormal
        ),
        QuickRule(
            name: "gotta → got to",
            description: "Replace 'gotta' with 'got to'",
            pattern: "\\bgotta\\b",
            replacement: "got to",
            isRegex: true,
            category: .casualToFormal
        ),
        QuickRule(
            name: "shoulda → should have",
            description: "Replace 'shoulda' with 'should have'",
            pattern: "\\bshoulda\\b",
            replacement: "should have",
            isRegex: true,
            category: .casualToFormal
        ),
        QuickRule(
            name: "woulda → would have",
            description: "Replace 'woulda' with 'would have'",
            pattern: "\\bwoulda\\b",
            replacement: "would have",
            isRegex: true,
            category: .casualToFormal
        ),
        QuickRule(
            name: "coulda → could have",
            description: "Replace 'coulda' with 'could have'",
            pattern: "\\bcoulda\\b",
            replacement: "could have",
            isRegex: true,
            category: .casualToFormal
        ),
        
        // Filler Words
        QuickRule(
            name: "Remove 'um'",
            description: "Remove filler word 'um'",
            pattern: "\\bum\\b",
            replacement: "",
            isRegex: true,
            isEnabled: false,
            category: .fillerWords
        ),
        QuickRule(
            name: "Remove 'uh'",
            description: "Remove filler word 'uh'",
            pattern: "\\buh\\b",
            replacement: "",
            isRegex: true,
            isEnabled: false,
            category: .fillerWords
        ),
        QuickRule(
            name: "Remove 'like' (filler)",
            description: "Remove 'like' when used as filler (surrounded by spaces)",
            pattern: "\\s+like\\s+",
            replacement: " ",
            isRegex: true,
            isEnabled: false,
            category: .fillerWords
        ),
        QuickRule(
            name: "Remove 'you know'",
            description: "Remove filler phrase 'you know'",
            pattern: "\\byou know\\b",
            replacement: "",
            isRegex: true,
            isEnabled: false,
            category: .fillerWords
        ),
        
        // Duplicates
        QuickRule(
            name: "Remove duplicate words",
            description: "Remove consecutive duplicate words (e.g., 'the the' → 'the')",
            pattern: "\\b(\\w+)\\s+\\1\\b",
            replacement: "$1",
            isRegex: true,
            category: .duplicates
        ),
        
        // Spacing
        QuickRule(
            name: "Fix multiple spaces",
            description: "Replace multiple spaces with single space",
            pattern: "\\s{2,}",
            replacement: " ",
            isRegex: true,
            category: .spacing
        ),
        QuickRule(
            name: "Trim whitespace",
            description: "Remove leading and trailing whitespace",
            pattern: "^\\s+|\\s+$",
            replacement: "",
            isRegex: true,
            category: .spacing
        ),
        QuickRule(
            name: "Fix space before punctuation",
            description: "Remove space before punctuation marks",
            pattern: "\\s+([.,!?;:])",
            replacement: "$1",
            isRegex: true,
            category: .spacing
        ),
        
        // Punctuation
        QuickRule(
            name: "Add space after punctuation",
            description: "Ensure space after punctuation marks",
            pattern: "([.,!?;:])([A-Za-z])",
            replacement: "$1 $2",
            isRegex: true,
            isEnabled: false,
            category: .punctuation
        ),
    ]
    
    /// Check if quick rules are enabled
    var isEnabled: Bool {
        get {
            AppSettings.QuickRules.isEnabled
        }
        set {
            AppSettings.QuickRules.isEnabled = newValue
        }
    }
    
    /// Load rules from UserDefaults, or return defaults if none saved
    func loadRules() -> [QuickRule] {
        guard let data = AppSettings.QuickRules.rulesData else {
            return Self.defaultRules
        }
        do {
            return try JSONDecoder().decode([QuickRule].self, from: data)
        } catch {
            AppLogger.storage.error("Failed to decode quick rules: \(error.localizedDescription)")
            return Self.defaultRules
        }
    }
    
    /// Save rules to UserDefaults
    func saveRules(_ rules: [QuickRule]) {
        do {
            let data = try JSONEncoder().encode(rules)
            AppSettings.QuickRules.rulesData = data
        } catch {
            AppLogger.storage.error("Failed to encode quick rules: \(error.localizedDescription)")
        }
    }
    
    /// Reset to default rules
    func resetToDefaults() {
        saveRules(Self.defaultRules)
    }
    
    /// Apply quick rules to text
    func applyRules(to text: String, rules: [QuickRule]) -> String {
        guard isEnabled else { return text }
        
        var processed = text
        let enabledRules = rules.filter { $0.isEnabled }
        
        for rule in enabledRules {
            if rule.isRegex {
                do {
                    let regex = try NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive)
                    let range = NSRange(processed.startIndex..., in: processed)
                    processed = regex.stringByReplacingMatches(
                        in: processed,
                        options: [],
                        range: range,
                        withTemplate: rule.replacement
                    )
                } catch {
                    AppLogger.storage.error("Invalid quick rule regex '\(rule.pattern)': \(error.localizedDescription)")
                }
            } else {
                processed = processed.replacingOccurrences(
                    of: rule.pattern,
                    with: rule.replacement,
                    options: .caseInsensitive
                )
            }
        }
        
        return processed
    }
    
    /// Apply quick rules to text (convenience method using stored rules)
    func applyRules(to text: String) -> String {
        let rules = loadRules()
        return applyRules(to: text, rules: rules)
    }
}
