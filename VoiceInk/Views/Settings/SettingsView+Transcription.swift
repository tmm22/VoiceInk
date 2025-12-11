import SwiftUI

// MARK: - Transcription Settings

extension SettingsView {
    var transcriptionSettings: some View {
        VStack(spacing: VoiceInkSpacing.md) {
            if sectionMatches("Dictionary", in: .transcription) {
                VoiceInkSection(
                    icon: "character.book.closed.fill",
                    title: "Dictionary",
                    subtitle: "Custom words and phrases"
                ) {
                    VStack(alignment: .leading, spacing: VoiceInkSpacing.sm) {
                        Text("Manage quick rules, word replacements, and correct spellings to improve transcription accuracy.")
                            .settingsDescription()
                        
                        Button("Open Dictionary Settings") {
                            showDictionarySheet = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            }
            
            if sectionMatches("Clipboard & Paste", in: .transcription) {
                ClipboardPasteSection()
            }
            
            if sectionMatches("Recorder Style", in: .transcription) {
                VoiceInkSection(
                    icon: "rectangle.on.rectangle",
                    title: "Recorder Style",
                    subtitle: "Choose your preferred recorder interface"
                ) {
                    Picker("Recorder Style", selection: $whisperState.recorderType) {
                        Text("Notch Recorder").tag("notch")
                        Text("Mini Recorder").tag("mini")
                    }
                    .pickerStyle(.radioGroup)
                }
            }
            
            if sectionMatches("Power Mode", in: .transcription) {
                PowerModeSettingsSection()
            }
            
            if sectionMatches("Experimental", in: .transcription) {
                ExperimentalFeaturesSection()
            }
        }
    }
}