import SwiftUI
import AppKit

struct TTSInspectorView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @Binding var isVisible: Bool
    
    // Track expanded state of sections
    @State private var isVoiceExpanded = true
    @State private var isAudioExpanded = true
    @State private var isExportExpanded = false
    @State private var isCostExpanded = false
    @State private var isSystemExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Tickwick Settings", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Hide Tickwick Settings")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Voice Configuration
                    DisclosureGroup(
                        isExpanded: $isVoiceExpanded,
                        content: {
                            VStack(spacing: 16) {
                                ProviderSelectionView()
                                VoiceSelectionView()
                                VoiceStyleControlsView()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        },
                        label: {
                            InspectorSectionHeader(title: "Voice Configuration", icon: "person.wave.2", isExpanded: isVoiceExpanded)
                        }
                    )
                    
                    Divider()
                    
                    // Audio & Playback
                    DisclosureGroup(
                        isExpanded: $isAudioExpanded,
                        content: {
                            VStack(spacing: 16) {
                                AudioSettingsView()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        },
                        label: {
                            InspectorSectionHeader(title: "Audio & Playback", icon: "speaker.wave.2", isExpanded: isAudioExpanded)
                        }
                    )
                    
                    Divider()
                    
                    // Export Settings
                    DisclosureGroup(
                        isExpanded: $isExportExpanded,
                        content: {
                            VStack(spacing: 16) {
                                ExportSettingsView()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        },
                        label: {
                            InspectorSectionHeader(title: "Export", icon: "square.and.arrow.down", isExpanded: isExportExpanded)
                        }
                    )
                    
                    Divider()
                    
                    // Cost & Usage
                    DisclosureGroup(
                        isExpanded: $isCostExpanded,
                        content: {
                            VStack(spacing: 16) {
                                CostView()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        },
                        label: {
                            InspectorSectionHeader(title: "Cost & Usage", icon: "dollarsign.circle", isExpanded: isCostExpanded)
                        }
                    )
                    
                    Divider()
                    
                    // System / Batch
                    DisclosureGroup(
                        isExpanded: $isSystemExpanded,
                        content: {
                            VStack(spacing: 16) {
                                SystemSettingsView()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        },
                        label: {
                            InspectorSectionHeader(title: "System", icon: "gear", isExpanded: isSystemExpanded)
                        }
                    )
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Subviews

private struct InspectorSectionHeader: View {
    let title: String
    let icon: String
    let isExpanded: Bool
    
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

private struct ProviderSelectionView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provider")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker("", selection: $viewModel.selectedProvider) {
                ForEach(TTSProviderType.allCases, id: \.self) { provider in
                    Label(provider.displayName, systemImage: provider.icon)
                        .tag(provider)
                }
            }
            .labelsHidden()
            .onChange(of: viewModel.selectedProvider) {
                viewModel.updateAvailableVoices()
            }
            
            let profile = ProviderCostProfile.profile(for: viewModel.selectedProvider)
            Text(profile.detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VoiceSelectionView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @State private var showingPreview = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Voice")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !viewModel.availableVoices.isEmpty {
                    Button {
                        if viewModel.isPreviewPlaying {
                            viewModel.stopPreview()
                        } else if let voice = viewModel.selectedVoice {
                            viewModel.previewVoice(voice)
                        }
                    } label: {
                        Image(systemName: viewModel.isPreviewPlaying ? "stop.fill" : "play.circle")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Preview selected voice")
                }
            }
            
            Picker("", selection: $viewModel.selectedVoice) {
                Text("Default").tag(nil as Voice?)
                ForEach(viewModel.availableVoices) { voice in
                    Text(voice.name).tag(voice as Voice?)
                }
            }
            .labelsHidden()
            
            if let voice = viewModel.selectedVoice {
                HStack(spacing: 8) {
                    Text(voice.language)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                    
                    if !viewModel.canPreview(voice) {
                        Image(systemName: "key.slash")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .help("API Key required for preview")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VoiceStyleControlsView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.hasActiveStyleControls {
                Divider()
                
                HStack {
                    Text("Style Controls")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Reset") {
                        viewModel.resetStyleControls()
                    }
                    .controlSize(.small)
                    .disabled(!viewModel.canResetStyleControls)
                }
                
                ForEach(viewModel.activeStyleControls) { control in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(control.label)
                                .font(.caption)
                            Spacer()
                            Text(control.formattedValue(for: viewModel.currentStyleValue(for: control)))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if let step = control.step {
                            Slider(value: viewModel.binding(for: control), in: control.range, step: step)
                        } else {
                            Slider(value: viewModel.binding(for: control), in: control.range)
                        }
                    }
                }
            }
            
            if viewModel.selectedProvider == .elevenLabs {
                Divider()
                ElevenLabsPromptingView()
            }
        }
    }
}

private struct AudioSettingsView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Speed
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Playback Speed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(viewModel.playbackSpeed, specifier: "%.2g")×")
                        .font(.caption)
                }
                
                HStack {
                    Image(systemName: "tortoise")
                        .font(.caption2)
                    Slider(value: $viewModel.playbackSpeed, in: 0.5...2.0, step: 0.25) { editing in
                        if !editing {
                            viewModel.applyPlaybackSpeed(save: true)
                        }
                    }
                    Image(systemName: "hare")
                        .font(.caption2)
                }
            }
            
            // Volume
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Volume")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(viewModel.volume * 100))%")
                        .font(.caption)
                }
                
                HStack {
                    Image(systemName: "speaker.fill")
                        .font(.caption2)
                    Slider(value: $viewModel.volume, in: 0...1) { editing in
                        if !editing {
                            viewModel.applyPlaybackVolume(save: true)
                        }
                    }
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption2)
                }
            }
            
            Divider()
            
            Toggle(isOn: $viewModel.isLoopEnabled) {
                Text("Loop Playback")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .onChange(of: viewModel.isLoopEnabled) {
                viewModel.saveSettings()
            }
        }
    }
}

private struct ExportSettingsView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @State private var selectedTranscriptFormat: TranscriptFormat = .srt
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Audio Format")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $viewModel.selectedFormat) {
                    ForEach(viewModel.supportedFormats, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .labelsHidden()
                
                if let help = viewModel.exportFormatHelpText {
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
                    Picker("", selection: $selectedTranscriptFormat) {
                        Text("SRT").tag(TranscriptFormat.srt)
                        Text("VTT").tag(TranscriptFormat.vtt)
                    }
                    .frame(width: 80)
                    .labelsHidden()
                    
                    Button {
                        viewModel.exportTranscript(format: selectedTranscriptFormat)
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

private struct CostView: View {
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
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
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

private struct SystemSettingsView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { viewModel.notificationsEnabled },
                set: { viewModel.setNotificationsEnabled($0) }
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
