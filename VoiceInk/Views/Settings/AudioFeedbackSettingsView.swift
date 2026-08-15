import SwiftUI
import UniformTypeIdentifiers

struct AudioFeedbackSettingsView: View {
    @ObservedObject private var soundManager = SoundManager.shared
    @State private var showingFilePicker = false
    @State private var currentSoundType: SoundType?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable sound feedback", isOn: $soundManager.settings.isEnabled)
                .toggleStyle(.switch)
            
            if soundManager.settings.isEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sound Theme")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Picker("Preset", selection: $soundManager.settings.preset) {
                        ForEach(AudioPreset.allCases, id: \.self) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: soundManager.settings.preset) { _, newPreset in
                        soundManager.settings.volumes = newPreset.defaultVolumes
                        soundManager.settings.customSounds = nil
                    }
                }
                .padding(.vertical, 4)
                
                if soundManager.settings.preset != .silent {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Volume Controls")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        volumeControl(
                            title: "Start Recording",
                            value: $soundManager.settings.volumes.start,
                            soundType: .start
                        )
                        
                        volumeControl(
                            title: "Stop Recording",
                            value: $soundManager.settings.volumes.stop,
                            soundType: .stop
                        )
                        
                        volumeControl(
                            title: "Cancel/Escape",
                            value: $soundManager.settings.volumes.cancel,
                            soundType: .cancel
                        )
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Custom Sounds")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if soundManager.settings.customSounds != nil {
                                Button("Reset to Preset") {
                                    soundManager.resetToPresetDefaults()
                                }
                                .buttonStyle(.link)
                                .controlSize(.small)
                            }
                        }
                        
                        Text("Override preset sounds with your own audio files (.mp3, .wav, .aiff)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        customSoundRow(
                            title: "Start Sound",
                            type: .start,
                            currentPath: soundManager.settings.customSounds?.startPath
                        )
                        
                        customSoundRow(
                            title: "Stop Sound",
                            type: .stop,
                            currentPath: soundManager.settings.customSounds?.stopPath
                        )
                        
                        customSoundRow(
                            title: "Cancel Sound",
                            type: .cancel,
                            currentPath: soundManager.settings.customSounds?.cancelPath
                        )
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio, .mp3, .wav, .aiff],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result: result)
        }
    }
    
    @ViewBuilder
    private func volumeControl(title: String, value: Binding<Float>, soundType: SoundType) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .frame(width: 110, alignment: .leading)
            
            Slider(value: value, in: 0...1, step: 0.05)
                .frame(maxWidth: 200)
            
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
            
            Button(action: {
                soundManager.previewSound(type: soundType)
            }) {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Preview sound")
        }
    }
    
    @ViewBuilder
    private func customSoundRow(title: String, type: SoundType, currentPath: String?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .frame(width: 90, alignment: .leading)
            
            if let path = currentPath {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Button(action: {
                    soundManager.setCustomSound(type: type, url: nil)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove custom sound")
            } else {
                Text("Using preset default")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .italic()
            }
            
            Spacer()
            
            Button(action: {
                currentSoundType = type
                showingFilePicker = true
            }) {
                Label(currentPath == nil ? "Choose File" : "Change", systemImage: "folder")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    private func handleFileSelection(result: Result<[URL], Error>) {
        guard let type = currentSoundType else { return }
        
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                soundManager.setCustomSound(type: type, url: url)
            }
            
        case .failure(let error):
            print("Error selecting audio file: \(error.localizedDescription)")
        }
        
        currentSoundType = nil
    }
}

#Preview {
    AudioFeedbackSettingsView()
        .frame(width: 500)
        .padding()
}
