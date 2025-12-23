import Foundation

extension TTSSettingsViewModel {
    func saveSnippet(named name: String, content: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedContent.isEmpty else { return }

        textSnippets.removeAll { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }

        let snippet = TextSnippet(name: trimmedName, content: trimmedContent)
        textSnippets.insert(snippet, at: 0)
        persistSnippets()
    }

    func removeSnippet(_ snippet: TextSnippet) {
        textSnippets.removeAll { $0.id == snippet.id }
        persistSnippets()
    }

    func insertSnippet(_ snippet: TextSnippet, into text: String, mode: SnippetInsertMode) -> String {
        switch mode {
        case .replace:
            return snippet.content
        case .append:
            if text.isEmpty {
                return snippet.content
            }
            return text + "\n\n" + snippet.content
        }
    }

    func persistSnippets() {
        do {
            let data = try JSONEncoder().encode(textSnippets)
            AppSettings.TTS.snippetsData = data
        } catch {
            AppLogger.storage.error("Failed to persist text snippets: \(error.localizedDescription)")
        }
    }
}
