import SwiftUI

struct PlaybackControlsView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @EnvironmentObject var settings: TTSSettingsViewModel
    @EnvironmentObject var playback: TTSPlaybackViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDraggingSlider = false
    @State private var temporaryTime: TimeInterval = 0
    
    var body: some View {
        VStack(spacing: 16) {
            // Main playback controls and progress
            HStack(spacing: settings.isMinimalistMode ? 12 : 20) {
                // Playback buttons
                HStack(spacing: settings.isMinimalistMode ? 8 : 12) {
                    // Skip backward
                    Button(action: {
                        playback.skipBackward()
                    }) {
                        Label("Skip backward 10 seconds", systemImage: "gobackward.10")
                            .labelStyle(.iconOnly)
                            .font(.system(size: settings.isMinimalistMode ? 16 : 20))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(!viewModel.hasGeneratedAudio || playback.duration <= 0)
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .accessibilityLabel("Skip backward 10 seconds")
                    .help("Skip backward 10 seconds (⌘←)")
                    
                    // Play/Pause
                    Button(action: {
                        playback.togglePlayPause()
                    }) {
                        Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.system(size: settings.isMinimalistMode ? 32 : 44))
                            .foregroundColor(.accentColor)
                            .scaleEffect(!reduceMotion && playback.isPlaying ? 1.1 : 1.0)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: playback.isPlaying)
                            .frame(width: settings.isMinimalistMode ? 36 : 48, height: settings.isMinimalistMode ? 36 : 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(!viewModel.hasGeneratedAudio)
                    .keyboardShortcut(.space, modifiers: [])
                    .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                    .help("Play/Pause (Space)")
                    
                    // Skip forward
                    Button(action: {
                        playback.skipForward()
                    }) {
                        Label("Skip forward 10 seconds", systemImage: "goforward.10")
                            .labelStyle(.iconOnly)
                            .font(.system(size: settings.isMinimalistMode ? 16 : 20))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(!viewModel.hasGeneratedAudio)
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .accessibilityLabel("Skip forward 10 seconds")
                    .help("Skip forward 10 seconds (⌘→)")
                    
                    // Stop
                    Button(action: playback.stop) {
                        Label("Stop", systemImage: "stop.circle")
                            .labelStyle(.iconOnly)
                            .font(.system(size: settings.isMinimalistMode ? 16 : 20))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(!viewModel.hasGeneratedAudio || !playback.isPlaying)
                    .keyboardShortcut(".", modifiers: .command)
                    .accessibilityLabel("Stop")
                    .help("Stop playback (⌘.)")
                }
                
                Divider()
                    .frame(height: settings.isMinimalistMode ? 24 : 30)
                
                // Progress bar and time
                HStack(spacing: 12) {
                    Text(formatTime(playback.currentTime))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                    
                    Slider(
                        value: Binding(
                            get: { min(max(isDraggingSlider ? temporaryTime : playback.currentTime, 0), timelineDuration) },
                            set: { temporaryTime = min(max($0, 0), timelineDuration) }
                        ),
                        in: 0...timelineDuration
                    ) { editing in
                        isDraggingSlider = editing
                        if !editing {
                            playback.seek(to: temporaryTime)
                        }
                    }
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(formatTime(isDraggingSlider ? temporaryTime : playback.currentTime)) of \(formatTime(playback.duration))")
                    .disabled(!viewModel.hasGeneratedAudio || playback.duration <= 0)
                    
                    Text(formatTime(playback.duration))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)
                }
                .frame(maxWidth: 400)
            }
            
            Divider()
            
                        // Speed and Volume controls (hidden in Minimalist mode - available via Advanced panel)
                        if !settings.isMinimalistMode {
                            HStack(spacing: 30) {
                                // Speed control
                                HStack(spacing: 8) {
                                    Image(systemName: "speedometer")
                                        .foregroundColor(.secondary)
                                    
                                    Text("Speed:")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                    
                                    Picker("Playback speed", selection: $playback.playbackSpeed) {
                                        Text("0.5×").tag(0.5)
                                        Text("0.75×").tag(0.75)
                                        Text("1.0×").tag(1.0)
                                        Text("1.25×").tag(1.25)
                                        Text("1.5×").tag(1.5)
                                        Text("1.75×").tag(1.75)
                                        Text("2.0×").tag(2.0)
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .labelsHidden()
                                    .frame(width: 80)
                                    .onChange(of: playback.playbackSpeed) {
                                        playback.applyPlaybackSpeed(save: true)
                                    }
                                    
                                    // Quick speed buttons
                                    HStack(spacing: 4) {
                                        Button(action: {
                                            playback.playbackSpeed = max(0.5, playback.playbackSpeed - 0.25)
                                        }) {
                                            Label("Decrease speed", systemImage: "minus.circle")
                                                .labelStyle(.iconOnly)
                                                .font(.system(size: 14))
                                                .frame(width: 24, height: 24)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel("Decrease speed")
                                        .keyboardShortcut("[", modifiers: .command)
                                        .help("Decrease speed (⌘[)")
                                        
                                        Button(action: {
                                            playback.playbackSpeed = min(2.0, playback.playbackSpeed + 0.25)
                                        }) {
                                            Label("Increase speed", systemImage: "plus.circle")
                                                .labelStyle(.iconOnly)
                                                .font(.system(size: 14))
                                                .frame(width: 24, height: 24)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel("Increase speed")
                                        .keyboardShortcut("]", modifiers: .command)
                                        .help("Increase speed (⌘])")
                                    }
                                }
                                
                                Divider()
                                    .frame(height: settings.isMinimalistMode ? 16 : 20)
                                
                                // Volume control
                                HStack(spacing: 8) {
                                    Image(systemName: volumeIcon)
                                        .foregroundColor(.secondary)
                                        .frame(width: 20)
                                    
                                    Text("Volume:")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                    
                                    Slider(value: $playback.volume, in: 0...1) { editing in
                                        if !editing {
                                            playback.applyPlaybackVolume(save: true)
                                        }
                                    }
                                    .onChange(of: playback.volume) {
                                        playback.applyPlaybackVolume()
                                    }
                                    .frame(width: 150)
                                    .accessibilityLabel("Volume")
                                    .accessibilityValue("\(Int(playback.volume * 100)) percent")
                                    
                                    Text("\(Int(playback.volume * 100))%")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 40, alignment: .trailing)
                                    
                                    // Mute button
                                    Button(action: {
                                        if playback.volume > 0 {
                                            playback.volume = 0
                                        } else {
                                            playback.volume = 0.75
                                        }
                                        playback.applyPlaybackVolume(save: true)
                                    }) {
                                        Label(playback.volume == 0 ? "Unmute" : "Mute", systemImage: playback.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                            .labelStyle(.iconOnly)
                                            .font(.system(size: 14))
                                            .frame(width: 24, height: 24)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(playback.volume == 0 ? "Unmute" : "Mute")
                                    .help("Toggle mute")
                                }
                                
                                Spacer()
                                
                                // Audio format indicator (if available)
                                if viewModel.hasGeneratedAudio {
                                    HStack(spacing: 4) {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        Text("Audio Ready")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                        }
        }
    }
    
    private var volumeIcon: String {
        if playback.volume == 0 {
            return "speaker.slash"
        } else if playback.volume < 0.33 {
            return "speaker"
        } else if playback.volume < 0.66 {
            return "speaker.wave.1"
        } else {
            return "speaker.wave.2"
        }
    }

    private var timelineDuration: Double {
        max(playback.duration, 0.01)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN && !time.isInfinite else { return "00:00" }
        
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%d:%02d:%02d", hours, remainingMinutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// Preview
struct PlaybackControlsView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = TTSViewModel()
        PlaybackControlsView()
            .environmentObject(viewModel)
            .environmentObject(viewModel.settings)
            .environmentObject(viewModel.playback)
            .frame(width: 800, height: 150)
            .padding()
    }
}
