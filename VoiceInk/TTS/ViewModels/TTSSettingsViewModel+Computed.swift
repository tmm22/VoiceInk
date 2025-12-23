import SwiftUI

extension TTSSettingsViewModel {
    var supportedFormats: [AudioSettings.AudioFormat] {
        supportedFormats(for: selectedProvider)
    }

    var currentCharacterLimit: Int {
        characterLimit(for: selectedProvider)
    }

    var exportFormatHelpText: String? {
        switch selectedProvider {
        case .elevenLabs:
            return "ElevenLabs currently exports MP3 files only."
        case .google:
            return "Google Cloud supports MP3 or WAV output."
        case .openAI:
            return "OpenAI offers MP3, WAV, AAC, and FLAC options."
        case .tightAss:
            return "Tight Ass Mode saves audio using the system voices in WAV format."
        }
    }

    var hasActiveStyleControls: Bool {
        !activeStyleControls.isEmpty
    }

    var canResetStyleControls: Bool {
        guard hasActiveStyleControls else { return false }
        return activeStyleControls.contains { canResetStyleControl($0) }
    }

    var colorSchemeOverride: ColorScheme? {
        appearancePreference.colorScheme
    }
}
