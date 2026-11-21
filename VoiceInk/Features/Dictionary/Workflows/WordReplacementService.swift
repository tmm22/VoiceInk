import Foundation
import SwiftData

class WordReplacementService {
    static let shared = WordReplacementService()

    // Word chars are Unicode letters/marks/digits (not just ASCII) so triggers can't match inside
    // words like "vergrößern"; non-spaced scripts are exempt so Latin triggers flush against
    // CJK/Thai still match (mirrors usesWordBoundaries). scx (Script_Extensions) so shared marks
    // like the prolonged sound mark U+30FC (Script=Common, scx=Hira Kana) stay exempt too.
    private static let wordChar =
        "[[\\p{L}\\p{M}\\p{N}]-[\\p{scx=Han}\\p{scx=Hiragana}\\p{scx=Katakana}\\p{scx=Hangul}\\p{scx=Thai}]]"

    /// Compiled boundary patterns by trigger. Compiling one takes about a millisecond on the main
    /// actor between transcription and paste, and the same triggers are applied to every
    /// dictation, so each is compiled once. The replacement text is not part of the pattern, so
    /// edits to it need no invalidation.
    private let boundaryRegexCache: NSCache<NSString, NSRegularExpression> = {
        let cache = NSCache<NSString, NSRegularExpression>()
        cache.countLimit = 2_000
        return cache
    }()

    private init() {}

    func applyReplacements(to text: String, using context: ModelContext) -> String {
        let descriptor = FetchDescriptor<WordReplacement>(
            predicate: #Predicate { $0.isEnabled }
        )

        guard let replacements = try? context.fetch(descriptor), !replacements.isEmpty else {
            return text  // No replacements to apply
        }

        var modifiedText = text

        // Longest-first so specific triggers match before shorter overlapping ones
        let sortedReplacements = replacements.sorted {
            $0.originalText.count > $1.originalText.count
        }

        // Apply replacements (case-insensitive)
        for replacement in sortedReplacements {
            let originalGroup = replacement.originalText
            let replacementText = replacement.replacementText

            let variants =
                originalGroup
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted { $0.count > $1.count }

            for original in variants {
                let usesBoundaries = usesWordBoundaries(for: original)

                if usesBoundaries {
                    if let regex = boundaryRegex(for: original) {
                        let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                        modifiedText = regex.stringByReplacingMatches(
                            in: modifiedText,
                            options: [],
                            range: range,
                            withTemplate: replacementText
                        )
                    }
                } else {
                    // Fallback substring replace for non-spaced scripts
                    modifiedText = modifiedText.replacingOccurrences(
                        of: original, with: replacementText, options: .caseInsensitive)
                }
            }
        }

        return modifiedText
    }

    /// The case-insensitive pattern that matches `original` as a whole word. Lookarounds instead
    /// of \b so punctuation acts as a word boundary.
    func boundaryRegex(for original: String) -> NSRegularExpression? {
        // A Foundation string compares code unit by code unit, so two triggers that are canonically
        // equivalent but encoded differently keep separate patterns, as when each was compiled per call.
        let key = NSString(string: original)
        if let cached = boundaryRegexCache.object(forKey: key) {
            return cached
        }

        let escaped = NSRegularExpression.escapedPattern(for: original)
        let pattern = "(?<!\(Self.wordChar))\(escaped)(?!\(Self.wordChar))"
        // A trigger whose pattern does not compile is skipped, as before. It is not cached.
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        boundaryRegexCache.setObject(regex, forKey: key)
        return regex
    }

    private func usesWordBoundaries(for text: String) -> Bool {
        // Returns false for languages without spaces (CJK, Thai), true for spaced languages
        let nonSpacedScripts: [ClosedRange<UInt32>] = [
            0x3040...0x309F,  // Hiragana
            0x30A0...0x30FF,  // Katakana
            0x4E00...0x9FFF,  // CJK Unified Ideographs
            0xAC00...0xD7AF,  // Hangul Syllables
            0x0E00...0x0E7F,  // Thai
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
