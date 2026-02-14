import SwiftUI

// MARK: - Audio Settings

extension SettingsView {
    var audioSettings: some View {
        VStack(spacing: VoiceInkSpacing.md) {
            if sectionMatches("Audio Input", in: .audio) {
                VoiceInkSection(
                    icon: "mic.fill",
                    title: "Audio Input",
                    subtitle: "Manage input devices"
                ) {
                    AudioInputSettingsView()
                }
            }
            
            if sectionMatches("Audio Feedback", in: .audio) {
                VoiceInkSection(
                    icon: "speaker.wave.2.bubble.left.fill",
                    title: "Audio Feedback",
                    subtitle: "Customize recording sounds and volumes"
                ) {
                    AudioFeedbackSettingsView()
                }
            }
            
            if sectionMatches("Recording Behavior", in: .audio) {
                VoiceInkSection(
                    icon: "waveform.badge.mic",
                    title: "Recording Behavior",
                    subtitle: "System audio settings"
                ) {
                    VStack(alignment: .leading, spacing: VoiceInkSpacing.sm) {
                        Toggle(isOn: $mediaController.isSystemMuteEnabled) {
                            Text("Mute system audio during recording")
                        }
                        .toggleStyle(.switch)
                        .help("Automatically mute system audio when recording starts and restore when recording stops")
                    }
                }
            }
        }
    }
}