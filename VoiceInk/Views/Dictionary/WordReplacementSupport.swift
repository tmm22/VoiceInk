import SwiftUI

extension String: @retroactive Identifiable {
    public var id: String { self }
}

enum WordReplacementSortMode: String {
    case originalAsc
    case originalDesc
    case replacementAsc
    case replacementDesc
}

enum WordReplacementSortColumn {
    case original
    case replacement
}

@MainActor
final class WordReplacementManager: ObservableObject {
    @Published var replacements: [String: String] {
        didSet {
            AppSettings.Dictionary.wordReplacements = replacements
        }
    }

    init() {
        replacements = AppSettings.Dictionary.wordReplacements
    }

    func addReplacement(original: String, replacement: String) {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        replacements[trimmed] = replacement
    }

    func removeReplacement(original: String) {
        replacements.removeValue(forKey: original)
    }

    func updateReplacement(oldOriginal: String, newOriginal: String, newReplacement: String) {
        replacements.removeValue(forKey: oldOriginal)
        let trimmed = newOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        replacements[trimmed] = newReplacement
    }
}
