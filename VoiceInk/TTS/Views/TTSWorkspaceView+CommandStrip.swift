import SwiftUI
import AppKit

// MARK: - Command Strip View

struct CommandStripView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @EnvironmentObject var settings: TTSSettingsViewModel
    @EnvironmentObject var importExport: TTSImportExportViewModel
    @EnvironmentObject var playback: TTSPlaybackViewModel
    @EnvironmentObject var generation: TTSSpeechGenerationViewModel
    @EnvironmentObject var preview: TTSVoicePreviewViewModel
    let constants: ResponsiveConstants
    let isCompact: Bool
    let isInspectorVisible: Bool
    @Binding var showingAbout: Bool
    @Binding var showingInspectorPopover: Bool
    let toggleInspector: () -> Void
    let focusInspector: () -> Void
    @State private var showingTranslationPopover = false
    @State private var showingPreviewPopover = false

    var body: some View {
        Group {
            if isCompact {
                wrappedLayout
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalLayout
                        .fixedSize(horizontal: true, vertical: false)
                    wrappedLayout
                    ScrollView(.horizontal, showsIndicators: false) {
                        horizontalLayout
                            .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .popover(isPresented: $showingInspectorPopover, arrowEdge: .top) {
            TTSInspectorView(isVisible: $showingInspectorPopover)
                .frame(width: 320, height: 500)
                .environmentObject(viewModel)
                .environmentObject(playback)
        }
    }

    private var horizontalLayout: some View {
        HStack(spacing: 12) {
            providerAndVoice
            Spacer(minLength: 12)
            statusIndicator
            generateButton
            actionsMenu
            inspectorToggleButton
            overflowMenu
        }
    }

    private var wrappedLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                providerAndVoice
                Spacer()
                statusIndicator
            }

            HStack(spacing: 12) {
                Spacer()
                generateButton
                actionsMenu
                inspectorToggleButton
                overflowMenu
            }
        }
    }

    private var providerAndVoice: some View {
        let pickerWidth: CGFloat = {
            switch constants.breakpoint {
            case .ultraCompact: return 120
            case .compact: return 140
            case .regular: return 160
            case .wide: return 180
            }
        }()
        
        return HStack(spacing: 12) {
            Picker("Provider", selection: $settings.selectedProvider) {
                ForEach(TTSProviderType.allCases, id: \.self) { provider in
                    Label(provider.displayName, systemImage: provider.icon)
                        .tag(provider)
                }
            }
            .onChange(of: settings.selectedProvider) {
                settings.updateAvailableVoices()
            }
            .frame(minWidth: pickerWidth)
            .pickerStyle(MenuPickerStyle())
            .help("Choose the speech provider")

            Picker("Voice", selection: $settings.selectedVoice) {
                Text("Default").tag(nil as Voice?)
                ForEach(settings.availableVoices) { voice in
                    Text(voice.name).tag(voice as Voice?)
                }
            }
            .frame(minWidth: pickerWidth)
            .pickerStyle(MenuPickerStyle())
            .help("Select the voice for this provider")
        }
    }

    private var voicePreviewButton: some View {
        Button {
            showingPreviewPopover = true
        } label: {
            Label(voicePreviewButtonText, systemImage: voicePreviewButtonIcon)
                .commandLabelFixedSize()
        }
        .buttonStyle(.bordered)
        .disabled(settings.availableVoices.isEmpty)
        .popover(isPresented: $showingPreviewPopover, arrowEdge: .top) {
            VoicePreviewPopover(isPresented: $showingPreviewPopover)
                .environmentObject(preview)
        }
        .help("Listen to sample audio for available voices")
    }

    private var voicePreviewButtonText: String {
        if preview.isPreviewPlaying, let name = preview.previewVoiceName {
            return "Previewing \(name)"
        } else if let name = preview.previewVoiceName {
            return "Preview: \(name)"
        } else {
            return "Preview Voice"
        }
    }

    private var voicePreviewButtonIcon: String {
        if preview.isPreviewLoadingActive {
            return "hourglass"
        } else if preview.isPreviewPlaying {
            return "speaker.wave.2.fill"
        } else {
            return "play.circle"
        }
    }

    private var characterCount: some View {
        let count = viewModel.effectiveCharacterCount
        let formattedLimit = settings.formattedCharacterLimit(for: settings.selectedProvider)
        let formattedCount = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
        return Label("Characters: \(formattedCount)/\(formattedLimit)", systemImage: "textformat.alt")
            .font(.footnote)
            .foregroundColor(viewModel.shouldHighlightCharacterOverflow ? .red : .secondary)
            .accessibilityLabel("Character count")
            .commandLabelFixedSize()
    }

    private var translationControl: some View {
        Button {
            showingTranslationPopover = true
        } label: {
            if viewModel.isTranslating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Translating…")
                }
                .commandLabelFixedSize()
            } else {
                Label("Translate", systemImage: "arrow.triangle.2.circlepath")
                    .commandLabelFixedSize()
            }
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $showingTranslationPopover, arrowEdge: .top) {
            TranslationSettingsPopover(isPresented: $showingTranslationPopover)
                .environmentObject(viewModel)
        }
        .help("Configure translation options and translate the current text")
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if generation.isGenerating {
            HStack(spacing: 6) {
                ProgressView(value: generation.generationProgress)
                    .frame(width: 80)
                Text("Generating")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .commandLabelFixedSize()
        } else if playback.isPlaying {
            Label("Playing", systemImage: "speaker.wave.2.fill")
                .font(.footnote)
                .foregroundColor(.green)
                .commandLabelFixedSize()
        }
    }

    private var batchButton: some View {
        Button(action: generation.startBatchGeneration) {
            Label("Batch", systemImage: "text.badge.plus")
                .commandLabelFixedSize()
        }
        .buttonStyle(.bordered)
        .disabled(!viewModel.hasBatchableSegments || generation.isGenerating || generation.isBatchRunning)
        .help("Generate every segment separated by ---")
    }

    private var generateButton: some View {
        Button {
            Task { await generation.generateSpeech() }
        } label: {
            Label("Generate", systemImage: "waveform")
                .fontWeight(.semibold)
                .commandLabelFixedSize()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || generation.isGenerating)
        .help("Generate speech from the editor text (⌘↵)")
    }

    private var exportButton: some View {
        Button(action: importExport.exportAudio) {
            Label("Export", systemImage: "square.and.arrow.down")
                .commandLabelFixedSize()
        }
        .buttonStyle(.bordered)
        .keyboardShortcut("e", modifiers: .command)
        .disabled(viewModel.audioData == nil)
        .help("Export the most recent audio file (⌘E)")
    }

    private var transcriptMenu: some View {
        Menu {
            Button("Export SRT") {
                importExport.exportTranscript(format: .srt)
            }
            Button("Export VTT") {
                importExport.exportTranscript(format: .vtt)
            }
        } label: {
            Label("Transcript", systemImage: "doc.text")
                .commandLabelFixedSize()
        }
        .disabled(viewModel.currentTranscript == nil)
        .help("Export the transcript for the current audio")
    }

    private var clearButton: some View {
        Button(action: viewModel.clearText) {
            Label("Clear", systemImage: "trash")
                .commandLabelFixedSize()
        }
        .buttonStyle(.bordered)
        .keyboardShortcut("k", modifiers: .command)
        .help("Clear the editor and audio (⌘K)")
    }
    
    private var actionsMenu: some View {
        Menu {
            Section("Voice") {
                Button {
                    showingPreviewPopover = true
                } label: {
                    Label("Preview Voices", systemImage: voicePreviewButtonIcon)
                }
                .disabled(settings.availableVoices.isEmpty)
            }
            
            Section("Text") {
                Button {
                    showingTranslationPopover = true
                } label: {
                    if viewModel.isTranslating {
                        Label("Translating…", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("Translate", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                
                Button(action: generation.startBatchGeneration) {
                    Label("Batch Generate", systemImage: "text.badge.plus")
                }
                .disabled(!viewModel.hasBatchableSegments || generation.isGenerating || generation.isBatchRunning)
                
                Button(action: viewModel.clearText) {
                    Label("Clear Text", systemImage: "trash")
                }
                .keyboardShortcut("k", modifiers: .command)
            }
            
            Section("Export") {
                Button(action: importExport.exportAudio) {
                    Label("Export Audio", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(viewModel.audioData == nil)
                
                Menu {
                    Button("Export SRT") {
                        importExport.exportTranscript(format: .srt)
                    }
                    Button("Export VTT") {
                        importExport.exportTranscript(format: .vtt)
                    }
                } label: {
                    Label("Export Transcript", systemImage: "doc.text")
                }
                .disabled(viewModel.currentTranscript == nil)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .imageScale(.large)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .help("Actions and tools")
    }
    
    @ViewBuilder
    private var inspectorToggleButton: some View {
        if settings.isInspectorEnabled {
            Button {
                toggleInspector()
            } label: {
                Image(systemName: isInspectorVisible ? "sidebar.right.fill" : "sidebar.right")
                    .imageScale(.large)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(isInspectorVisible ? "Hide Tickwick Settings" : "Show Tickwick Settings")
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button("View Cost Detail", systemImage: "dollarsign.circle") {
                focusInspector()
            }

            Menu("Appearance", systemImage: "paintbrush") {
                Picker("Appearance", selection: $settings.appearancePreference) {
                    ForEach(AppearancePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(.inline)
            }

            Button(settings.isMinimalistMode ? "Disable Compact Layout" : "Enable Compact Layout", systemImage: "rectangle.compress.vertical") {
                settings.isMinimalistMode.toggle()
            }

            Divider()

            Button("Settings", systemImage: "gear") {
                // Navigate to main app settings
                _ = WindowManager.shared.showMainWindow()
                NotificationCenter.default.post(
                    name: .navigateToDestination,
                    object: nil,
                    userInfo: ["destination": "Settings"]
                )
            }

            Button("About", systemImage: "info.circle") {
                showingAbout = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .imageScale(.large)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .help("More options")
    }
}

// MARK: - View Extension

extension View {
    func commandLabelFixedSize() -> some View {
        fixedSize(horizontal: true, vertical: false)
    }
}
