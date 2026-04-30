import SwiftUI
import AppKit

struct TTSInspectorSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        DisclosureGroup(
            isExpanded: $isExpanded,
            content: {
                VStack(spacing: 16) {
                    content()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            },
            label: {
                InspectorSectionHeader(title: title, icon: icon)
            }
        )
    }
}

struct InspectorSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

struct ProviderSelectionView: View {
    @EnvironmentObject var settings: TTSSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provider")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Provider", selection: $settings.selectedProvider) {
                ForEach(TTSProviderType.allCases, id: \.self) { provider in
                    Label(provider.displayName, systemImage: provider.icon)
                        .tag(provider)
                }
            }
            .labelsHidden()
            .onChange(of: settings.selectedProvider) {
                settings.updateAvailableVoices()
            }

            let profile = ProviderCostProfile.profile(for: settings.selectedProvider)
            Text(profile.detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VoiceSelectionView: View {
    @EnvironmentObject var settings: TTSSettingsViewModel
    @EnvironmentObject var preview: TTSVoicePreviewViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Voice")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if !settings.availableVoices.isEmpty {
                    Button {
                        if preview.isPreviewPlaying {
                            preview.stopPreview()
                        } else if let voice = settings.selectedVoice {
                            preview.previewVoice(voice)
                        }
                    } label: {
                        Label(preview.isPreviewPlaying ? "Stop voice preview" : "Preview selected voice", systemImage: preview.isPreviewPlaying ? "stop.fill" : "play.circle")
                            .labelStyle(.iconOnly)
                            .foregroundColor(.accentColor)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(preview.isPreviewPlaying ? "Stop voice preview" : "Preview selected voice")
                    .help("Preview selected voice")
                }
            }

            Picker("Voice", selection: $settings.selectedVoice) {
                Text("Default").tag(nil as Voice?)
                ForEach(settings.availableVoices) { voice in
                    Text(voice.name).tag(voice as Voice?)
                }
            }
            .labelsHidden()

            if let voice = settings.selectedVoice {
                HStack(spacing: 8) {
                    Text(voice.language)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)

                    if !preview.canPreview(voice) {
                        Image(systemName: "key.slash")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .help("API Key required for preview")
                    }
                }
            }

            if settings.canHideSelectedPocketVoice {
                Button(role: .destructive) {
                    settings.hideSelectedPocketVoice()
                } label: {
                    Label("Hide Selected Pocket Voice", systemImage: "eye.slash")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            if settings.hasHiddenPocketVoices {
                Menu {
                    ForEach(settings.sortedHiddenPocketVoiceIDs, id: \.self) { voiceID in
                        Button(settings.pocketVoiceDisplayName(for: voiceID)) {
                            settings.restorePocketVoice(withID: voiceID)
                        }
                    }

                    Divider()

                    Button("Restore All Pocket Voices") {
                        settings.restoreAllPocketVoices()
                    }
                } label: {
                    Label("Restore Hidden Pocket Voices", systemImage: "eye")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VoiceStyleControlsView: View {
    @EnvironmentObject var settings: TTSSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if settings.hasActiveStyleControls {
                Divider()

                HStack {
                    Text("Style Controls")
                        .font(.caption)
                        .fontWeight(.semibold)

                    Spacer()

                    Button("Reset") {
                        settings.resetStyleControls()
                    }
                    .controlSize(.small)
                    .disabled(!settings.canResetStyleControls)
                }

                ForEach(settings.activeStyleControls) { control in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(control.label)
                                .font(.caption)

                            Spacer()

                            Text(control.formattedValue(for: settings.currentStyleValue(for: control)))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if let step = control.step {
                            Slider(value: settings.binding(for: control), in: control.range, step: step)
                        } else {
                            Slider(value: settings.binding(for: control), in: control.range)
                        }
                    }
                }
            }

            if settings.selectedProvider == .elevenLabs {
                Divider()
                ElevenLabsPromptingView()
            }
        }
    }
}
