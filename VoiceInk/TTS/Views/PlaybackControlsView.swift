import SwiftUI

struct PlaybackControlsView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @EnvironmentObject var settings: TTSSettingsViewModel
    @EnvironmentObject var playback: TTSPlaybackViewModel
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
                        Image(systemName: "gobackward.10")
                            .font(.system(size: settings.isMinimalistMode ? 16 : 20))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.audioData == nil)
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .help("Skip backward 10 seconds (⌘←)")
                    
                    // Play/Pause
                    Button(action: {
                        playback.togglePlayPause()
                    }) {
                        Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: settings.isMinimalistMode ? 32 : 44))
                            .foregroundColor(.accentColor)
                            .scaleEffect(playback.isPlaying ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: playback.isPlaying)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.audioData == nil)
                    .keyboardShortcut(.space, modifiers: [])
                    .help("Play/Pause (Space)")
                    
                    // Skip forward
                    Button(action: {
                        playback.skipForward()
                    }) {
                        Image(systemName: "goforward.10")
                            .font(.system(size: settings.isMinimalistMode ? 16 : 20))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.audioData == nil)
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .help("Skip forward 10 seconds (⌘→)")
                    
                    // Stop
                    Button(action: playback.stop) {
                        Image(systemName: "stop.circle")
                            .font(.system(size: settings.isMinimalistMode ? 16 : 20))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.audioData == nil || !playback.isPlaying)
                    .keyboardShortcut(".", modifiers: .command)
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
                    
                    // Custom progress slider
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 6)
                            
                            // Progress track
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor)
                                .frame(
                                    width: playback.duration > 0 ? 
                                        geometry.size.width * CGFloat(isDraggingSlider ? temporaryTime : playback.currentTime) / CGFloat(playback.duration) : 0,
                                    height: 6
                                )
                            
                            // Draggable thumb
                            if playback.duration > 0 {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 14, height: 14)
                                    .offset(x: geometry.size.width * CGFloat(isDraggingSlider ? temporaryTime : playback.currentTime) / CGFloat(playback.duration) - 7)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                isDraggingSlider = true
                                                let progress = max(0, min(1, value.location.x / geometry.size.width))
                                                temporaryTime = playback.duration * Double(progress)
                                            }
                                            .onEnded { _ in
                                                playback.seek(to: temporaryTime)
                                                isDraggingSlider = false
                                            }
                                    )
                            }
                        }
                        .frame(height: 14)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let progress = max(0, min(1, location.x / geometry.size.width))
                            let newTime = playback.duration * Double(progress)
                            playback.seek(to: newTime)
                        }
                    }
                    .frame(height: 14)
                    .disabled(viewModel.audioData == nil)
                    
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
                                    
                                    Picker("", selection: $playback.playbackSpeed) {
                                        Text("0.5×").tag(0.5)
                                        Text("0.75×").tag(0.75)
                                        Text("1.0×").tag(1.0)
                                        Text("1.25×").tag(1.25)
                                        Text("1.5×").tag(1.5)
                                        Text("1.75×").tag(1.75)
                                        Text("2.0×").tag(2.0)
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .frame(width: 80)
                                    .onChange(of: playback.playbackSpeed) {
                                        playback.applyPlaybackSpeed(save: true)
                                    }
                                    
                                    // Quick speed buttons
                                    HStack(spacing: 4) {
                                        Button(action: {
                                            playback.playbackSpeed = max(0.5, playback.playbackSpeed - 0.25)
                                        }) {
                                            Image(systemName: "minus.circle")
                                                .font(.system(size: 14))
                                        }
                                        .buttonStyle(.plain)
                                        .keyboardShortcut("[", modifiers: .command)
                                        .help("Decrease speed (⌘[)")
                                        
                                        Button(action: {
                                            playback.playbackSpeed = min(2.0, playback.playbackSpeed + 0.25)
                                        }) {
                                            Image(systemName: "plus.circle")
                                                .font(.system(size: 14))
                                        }
                                        .buttonStyle(.plain)
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
                                        Image(systemName: playback.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                            .font(.system(size: 14))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Toggle mute")
                                }
                                
                                Spacer()
                                
                                // Audio format indicator (if available)
                                if viewModel.audioData != nil {
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
