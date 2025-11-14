import Foundation
import SwiftUI

class DictionaryContextService {
    static let shared = DictionaryContextService()
    
    private init() {}
    
    func getDictionaryContext() -> String {
        guard let customWords = getCustomDictionaryWords(), !customWords.isEmpty else {
            return ""
        }

        let wordsText = customWords.joined(separator: ", ")
        return "Important Vocabulary: \(wordsText)"
    }
    private func getCustomDictionaryWords() -> [String]? {
        guard let data = UserDefaults.standard.data(forKey: "CustomDictionaryItems") else {
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
}
