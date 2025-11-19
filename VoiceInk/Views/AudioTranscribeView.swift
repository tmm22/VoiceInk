import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AVFoundation

@MainActor
struct AudioTranscribeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var whisperState: WhisperState
    @StateObject private var transcriptionManager: AudioTranscriptionManager
    @State private var isDropTargeted = false
    @State private var selectedAudioURL: URL?
    @State private var isAudioFileSelected = false
    @State private var isEnhancementEnabled = false
    @State private var selectedPromptId: UUID?

    init(transcriptionManager: AudioTranscriptionManager) {
        _transcriptionManager = StateObject(wrappedValue: transcriptionManager)
    }

    @MainActor
    init() {
        _transcriptionManager = StateObject(wrappedValue: AudioTranscriptionManager.shared)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: VoiceInkSpacing.lg) {
                VoiceInkCard(padding: VoiceInkSpacing.xl) {
                    if transcriptionManager.isProcessing {
                        processingView
                    } else {
                        uploaderView
                    }
                }

                if let transcription = transcriptionManager.currentTranscription {
                    TranscriptionResultView(transcription: transcription)
                }
            }
            .padding(VoiceInkSpacing.lg)
        }
        .onDrop(of: [.fileURL, .data, .audio, .movie], isTargeted: $isDropTargeted) { providers in
            if !transcriptionManager.isProcessing && !isAudioFileSelected {
                handleDroppedFile(providers)
                return true
            }
            return false
        }
        .alert("Error", isPresented: .constant(transcriptionManager.errorMessage != nil)) {
            Button("OK", role: .cancel) {
                transcriptionManager.errorMessage = nil
            }
        } message: {
            if let errorMessage = transcriptionManager.errorMessage {
                Text(errorMessage)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileForTranscription)) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                validateAndSetAudioFile(url)
            }
        }
    }
    
    private var uploaderView: some View {
        VStack(spacing: VoiceInkSpacing.lg) {
            if isAudioFileSelected {
                selectedFileView
            } else {
                VoiceInkDropZone(
                    isActive: isDropTargeted,
                    title: "Drop audio or video file here",
                    subtitle: "Drag files directly into this window or choose a file manually.",
                    buttonTitle: "Choose File",
                    buttonAction: selectFile
                )
                .frame(height: 240)
            }

            Text("Supported formats: WAV, MP3, M4A, AIFF, MP4, MOV")
                .voiceInkCaptionStyle()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedFileView: some View {
        VStack(alignment: .leading, spacing: VoiceInkSpacing.lg) {
            if let fileName = selectedAudioURL?.lastPathComponent {
                Text("Audio file selected: \(fileName)")
                    .voiceInkHeadline()
            }

            if let enhancementService = whisperState.getEnhancementService() {
                enhancementControls(for: enhancementService)
                    .onAppear {
                        isEnhancementEnabled = enhancementService.isEnhancementEnabled
                        selectedPromptId = enhancementService.selectedPromptId
                    }
            }

            HStack(spacing: VoiceInkSpacing.sm) {
                Button("Start Transcription") {
                    if let url = selectedAudioURL {
                        transcriptionManager.startProcessing(
                            url: url,
                            modelContext: modelContext,
                            whisperState: whisperState
                        )
                    }
                }
                .buttonStyle(PrimaryProminentButtonStyle())

                Button("Choose Different File") {
                    selectedAudioURL = nil
                    isAudioFileSelected = false
                }
                .buttonStyle(SecondaryBorderedButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func enhancementControls(for service: AIEnhancementService) -> some View {
        VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
            HStack(spacing: VoiceInkSpacing.sm) {
                Toggle("AI Enhancement", isOn: $isEnhancementEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: isEnhancementEnabled) { _, newValue in
                        service.isEnhancementEnabled = newValue
                    }

                if isEnhancementEnabled {
                    Divider()
                        .frame(height: 20)

                    HStack(spacing: VoiceInkSpacing.xs) {
                        Text("Prompt")
                            .voiceInkSubheadline()

                        if service.allPrompts.isEmpty {
                            Text("No prompts available")
                                .voiceInkCaptionStyle()
                                .italic()
                        } else {
                            let promptBinding = Binding<UUID>(
                                get: {
                                    selectedPromptId ?? service.allPrompts.first?.id ?? UUID()
                                },
                                set: { newValue in
                                    selectedPromptId = newValue
                                    service.selectedPromptId = newValue
                                }
                            )

                            Picker("Prompt", selection: promptBinding) {
                                ForEach(service.allPrompts) { prompt in
                                    Text(prompt.title).tag(prompt.id)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
            }
        }
        .padding(VoiceInkSpacing.md)
        .voiceInkCardBackground()
    }
    
    private var processingView: some View {
        VStack(spacing: VoiceInkSpacing.md) {
            ProgressView()
                .controlSize(.large)

            Text(transcriptionManager.processingPhase.message)
                .voiceInkHeadline()
        }
        .frame(maxWidth: .infinity)
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .audio, .movie
        ]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                selectedAudioURL = url
                isAudioFileSelected = true
            }
        }
    }
    
    private func handleDroppedFile(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        
        // List of type identifiers to try
        let typeIdentifiers = [
            UTType.fileURL.identifier,
            UTType.audio.identifier,
            UTType.movie.identifier,
            UTType.data.identifier,
            "public.file-url"
        ]
        
        // Try each type identifier
        for typeIdentifier in typeIdentifiers {
            if provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { (item, error) in
                    if let error = error {
                        print("Error loading dropped file with type \(typeIdentifier): \(error)")
                        return
                    }
                    
                    var fileURL: URL?
                    
                    if let url = item as? URL {
                        fileURL = url
                    } else if let data = item as? Data {
                        // Try to create URL from data
                        if let url = URL(dataRepresentation: data, relativeTo: nil) {
                            fileURL = url
                        } else if let urlString = String(data: data, encoding: .utf8),
                                  let url = URL(string: urlString) {
                            fileURL = url
                        }
                    } else if let urlString = item as? String {
                        fileURL = URL(string: urlString)
                    }
                    
                    if let finalURL = fileURL {
                        DispatchQueue.main.async {
                            self.validateAndSetAudioFile(finalURL)
                        }
                        return
                    }
                }
                break // Stop trying other types once we find a compatible one
            }
        }
    }
    
    private func validateAndSetAudioFile(_ url: URL) {
        print("Attempting to validate file: \(url.path)")
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("File does not exist at path: \(url.path)")
            return
        }
        
        // Try to access security scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Validate file type
        guard SupportedMedia.isSupported(url: url) else { return }
        
        print("File validated successfully: \(url.lastPathComponent)")
        selectedAudioURL = url
        isAudioFileSelected = true
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
