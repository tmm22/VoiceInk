import SwiftUI

// MARK: - Translation Functionality
extension TTSViewModel {
    func translateCurrentText() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            errorMessage = "Please enter text to translate"
            return
        }

        guard canTranslate else {
            errorMessage = "Add an OpenAI key in Settings to translate text."
            return
        }

        isTranslating = true
        errorMessage = nil

        do {
            let result = try await translationService.translate(text: trimmed, targetLanguageCode: translationTargetLanguage.code)

            if translationKeepOriginal {
                translationResult = result
            } else {
                isUpdatingInputFromTranslation = true
                inputText = result.translatedText
                isUpdatingInputFromTranslation = false
                translationResult = nil
            }
        } catch let error as TTSError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isTranslating = false
    }

    func adoptTranslationAsInput() {
        guard let translationResult else { return }
        translationKeepOriginal = false
        isUpdatingInputFromTranslation = true
        inputText = translationResult.translatedText
        isUpdatingInputFromTranslation = false
        self.translationResult = nil
    }
}