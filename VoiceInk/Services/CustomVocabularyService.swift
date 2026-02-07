import Foundation
import SwiftData

class CustomVocabularyService {
    static let shared = CustomVocabularyService()

    private init() {}

    func getCustomVocabulary(from context: ModelContext) -> String {
        // The current vocabulary source is persisted JSON in AppSettings.
        // Keep the signature for compatibility with existing call sites.
        _ = context

        migrateOldDataIfNeeded()

        let customWords = getCustomVocabularyWords()
        guard !customWords.isEmpty else {
            return ""
        }

        return "Important Vocabulary: \(customWords.joined(separator: ", "))"
    }

    private func getCustomVocabularyWords() -> [String] {
        guard let data = AppSettings.Dictionary.customVocabularyItemsData else {
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        let words = json.compactMap { $0["word"] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var uniqueWords: [String] = []
        for word in words {
            let key = word.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                uniqueWords.append(word)
            }
        }
        return uniqueWords
    }

    private func migrateOldDataIfNeeded() {
        // Migrate from old "CustomDictionaryItems" key to new "CustomVocabularyItems" key.
        if AppSettings.Dictionary.customVocabularyItemsData == nil,
           let oldData = AppSettings.Dictionary.legacyCustomDictionaryItemsData {
            AppSettings.Dictionary.customVocabularyItemsData = oldData
            AppSettings.Dictionary.legacyCustomDictionaryItemsData = nil
        }
    }
}
