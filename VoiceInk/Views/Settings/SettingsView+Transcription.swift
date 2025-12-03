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
                VoiceInkSection(
                    icon: "doc.on.clipboard",
                    title: "Clipboard & Paste",
                    subtitle: "Choose how text is pasted and stored"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: "preserveTranscriptInClipboard") },
                            set: { UserDefaults.standard.set($0, forKey: "preserveTranscriptInClipboard") }
                        )) {
                            Text("Preserve transcript in clipboard")
                        }
                        .toggleStyle(.switch)
                        .help("Keep the transcribed text in clipboard instead of restoring the original clipboard content")
                        
                        Toggle("Use AppleScript Paste Method", isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: "UseAppleScriptPaste") },
                            set: { UserDefaults.standard.set($0, forKey: "UseAppleScriptPaste") }
                        ))
                        .toggleStyle(.switch)
                        .help("Use AppleScript if you have a non-standard keyboard layout")
                    }
                }
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