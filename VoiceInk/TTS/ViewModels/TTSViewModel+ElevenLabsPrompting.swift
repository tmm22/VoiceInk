import Foundation

// MARK: - ElevenLabs Prompting Helpers
extension TTSViewModel {
    func insertElevenLabsPromptAtTop() {
        let trimmedPrompt = elevenLabsPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        let promptBlock = "\(trimmedPrompt)\n\n"
        let existing = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        if existing.lowercased().hasPrefix(trimmedPrompt.lowercased()) {
            return
        }

        if existing.isEmpty {
            inputText = promptBlock
        } else {
            inputText = promptBlock + inputText
        }
    }

    func insertElevenLabsTag(_ rawToken: String) {
        let normalized = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        if inputText.isEmpty {
            inputText = normalized
        } else if inputText.hasSuffix("\n") {
            inputText.append(contentsOf: "\(normalized)\n")
        } else {
            inputText.append(contentsOf: "\n\(normalized)\n")
        }
    }

    func addElevenLabsTag(_ rawToken: String) {
        var normalized = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        if !normalized.hasPrefix("[") {
            normalized = "[\(normalized)"
        }
        if !normalized.hasSuffix("]") {
            normalized.append("]")
        }

        guard !elevenLabsTags.contains(normalized) else { return }
        elevenLabsTags.append(normalized)
    }

    func removeElevenLabsTag(_ token: String) {
        elevenLabsTags.removeAll { $0 == token }
    }

    func resetElevenLabsTagsToDefaults() {
        elevenLabsTags = ElevenLabsVoiceTag.defaultTokens
    }
}
