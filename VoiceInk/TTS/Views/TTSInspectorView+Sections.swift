import SwiftUI

struct AudioSettingsView: View {
    @EnvironmentObject var settings: TTSSettingsViewModel
    @EnvironmentObject var playback: TTSPlaybackViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Playback Speed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(playback.playbackSpeed, specifier: "%.2g")×")
                        .font(.caption)
                }

                HStack {
                    Image(systemName: "tortoise")
                        .font(.caption2)
                    Slider(value: $playback.playbackSpeed, in: 0.5...2.0, step: 0.25) { editing in
                        if !editing {
                            playback.applyPlaybackSpeed(save: true)
                        }
                    }
                    .accessibilityLabel("Playback speed")
                    .accessibilityValue(String(format: "%.2g times", playback.playbackSpeed))
                    Image(systemName: "hare")
                        .font(.caption2)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Volume")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(playback.volume * 100))%")
                        .font(.caption)
                }

                HStack {
                    Image(systemName: "speaker.fill")
                        .font(.caption2)
                    Slider(value: $playback.volume, in: 0...1) { editing in
                        if !editing {
                            playback.applyPlaybackVolume(save: true)
                        }
                    }
                    .accessibilityLabel("Volume")
                    .accessibilityValue("\(Int(playback.volume * 100)) percent")
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption2)
                }
            }

            Divider()

            Toggle(isOn: $playback.isLoopEnabled) {
                Text("Loop Playback")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .onChange(of: playback.isLoopEnabled) {
                settings.saveSettings()
            }
        }
    }
}

struct ExportSettingsView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @EnvironmentObject var settings: TTSSettingsViewModel
    @EnvironmentObject var importExport: TTSImportExportViewModel
    @State private var selectedTranscriptFormat: TranscriptFormat = .srt

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Audio Format")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Audio format", selection: $settings.selectedFormat) {
                    ForEach(settings.supportedFormats, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .labelsHidden()

                if let help = settings.exportFormatHelpText {
                    Text(help)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Transcript Export")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Picker("Transcript format", selection: $selectedTranscriptFormat) {
                        Text("SRT").tag(TranscriptFormat.srt)
                        Text("VTT").tag(TranscriptFormat.vtt)
                    }
                    .frame(width: 80)
                    .labelsHidden()

                    Button {
                        importExport.exportTranscript(format: selectedTranscriptFormat)
                    } label: {
                        Label("Export File", systemImage: "doc.text")
                    }
                    .disabled(viewModel.currentTranscript == nil)
                }

                if viewModel.currentTranscript == nil {
                    Text("Generate speech to create a transcript.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct CostView: View {
    @EnvironmentObject var viewModel: TTSViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Estimated Cost")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(viewModel.costEstimate.summary)
                        .font(.title2)
                        .fontWeight(.medium)
                }

                Spacer()

                Button {
                    viewModel.objectWillChange.send()
                } label: {
                    Label("Refresh estimate", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh estimate")
                .help("Refresh estimate")
            }

            if let detail = viewModel.costEstimate.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }

            Text("Character Count: \(viewModel.effectiveCharacterCount)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct SystemSettingsView: View {
    @EnvironmentObject var settings: TTSSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { settings.notificationsEnabled },
                set: { settings.setNotificationsEnabled($0) }
            )) {
                VStack(alignment: .leading) {
                    Text("Batch Notifications")
                    Text("Notify when background jobs complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }
}
