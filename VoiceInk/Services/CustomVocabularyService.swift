import Foundation
import SwiftUI

class CustomVocabularyService {
    static let shared = CustomVocabularyService()

    private init() {
        // Migrate old key to new key if needed
        migrateOldDataIfNeeded()
    }

    func getCustomVocabulary() -> String {
        guard let customWords = getCustomVocabularyWords(), !customWords.isEmpty else {
            return ""
        }

        let wordsText = customWords.joined(separator: ", ")
        return "Important Vocabulary: \(wordsText)"
    }

    private func getCustomVocabularyWords() -> [String]? {
        guard let data = AppSettings.Dictionary.customVocabularyItemsData else {
            return nil
        }

        do {
            let items = try JSONDecoder().decode([DictionaryItem].self, from: data)
            let words = items.map { $0.word }
            return words.isEmpty ? nil : words
        } catch {
            return nil
        }
    }

    private func migrateOldDataIfNeeded() {
        // Migrate from old "CustomDictionaryItems" key to new "CustomVocabularyItems" key
        if AppSettings.Dictionary.customVocabularyItemsData == nil,
           let oldData = AppSettings.Dictionary.legacyCustomDictionaryItemsData {
            AppSettings.Dictionary.customVocabularyItemsData = oldData
            AppSettings.Dictionary.legacyCustomDictionaryItemsData = nil
        }
    }
}
