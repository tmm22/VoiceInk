import Foundation
import SwiftData

class WordReplacementService {
    static let shared = WordReplacementService()

    private init() {}
    
    func applyReplacements(to text: String) -> String {
        // First apply quick rules if enabled
        var modifiedText = QuickRulesService.shared.applyRules(to: text)
        
        // Then apply custom word replacements
        let replacements = AppSettings.Dictionary.wordReplacements
        guard !replacements.isEmpty else {
            return modifiedText // No custom replacements to apply
        }
        
        // Apply longest keys first so specific triggers win over shorter overlaps.
        let sortedReplacements = replacements.sorted {
            $0.key.count > $1.key.count
        }

        // Apply replacements (case-insensitive)
        for replacement in sortedReplacements {
            let originalGroup = replacement.key
            let replacementText = replacement.value

            let variants = originalGroup
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted { $0.count > $1.count }

            for original in variants {
                let usesBoundaries = usesWordBoundaries(for: original)

                if usesBoundaries {
                    // Lookarounds handle punctuation-heavy terms like "C++" better than \b.
                    let escaped = NSRegularExpression.escapedPattern(for: original)
                    let pattern = "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
                    do {
                        let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                        let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                        modifiedText = regex.stringByReplacingMatches(
                            in: modifiedText,
                            options: [],
                            range: range,
                            withTemplate: replacementText
                        )
                    } catch {
                        AppLogger.transcription.error("Failed to compile word replacement pattern: \(AppLogger.errorMetadata(error), privacy: .public)")
                    }
                } else {
                    // Fallback substring replace for non-spaced scripts
                    modifiedText = modifiedText.replacingOccurrences(of: original, with: replacementText, options: .caseInsensitive)
                }
            }
        }

        return modifiedText
    }

    private func usesWordBoundaries(for text: String) -> Bool {
        // Returns false for languages without spaces (CJK, Thai), true for spaced languages
        let nonSpacedScripts: [ClosedRange<UInt32>] = [
            0x3040...0x309F, // Hiragana
            0x30A0...0x30FF, // Katakana
            0x4E00...0x9FFF, // CJK Unified Ideographs
            0xAC00...0xD7AF, // Hangul Syllables
            0x0E00...0x0E7F, // Thai
        ]

        for scalar in text.unicodeScalars {
            for range in nonSpacedScripts {
                if range.contains(scalar.value) {
                    return false
                }
            }
        }

        return true
    }
}
