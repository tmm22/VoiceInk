import Foundation

struct VocabularyWordData: Codable, Hashable {
    let word: String
    let dateAdded: Date?

    init(word: String, dateAdded: Date? = nil) {
        self.word = word
        self.dateAdded = dateAdded
    }
}
