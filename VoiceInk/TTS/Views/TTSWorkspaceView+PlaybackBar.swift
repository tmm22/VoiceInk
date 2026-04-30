import SwiftUI
import AppKit

// MARK: - Playback Bar View

struct PlaybackBarView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @EnvironmentObject var settings: TTSSettingsViewModel
    @EnvironmentObject var playback: TTSPlaybackViewModel
    @EnvironmentObject var generation: TTSSpeechGenerationViewModel
    @State private var isScrubbing = false
    @State private var temporaryTime: TimeInterval = 0
    @State private var showSegmentMarkers = false
    let horizontalPadding: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                transportControls

                Divider()
                    .frame(height: 24)

                timeline

                Divider()
                    .frame(height: 24)

                loopToggle
                speedPicker
                volumeSlider

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSegmentMarkers.toggle()
                    }
                } label: {
                    Label(
                        showSegmentMarkers ? "Hide segment markers" : "Show segment markers",
                        systemImage: showSegmentMarkers ? "chevron.down.circle" : "chevron.up.circle"
                    )
                        .labelStyle(.iconOnly)
                        .imageScale(.large)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(showSegmentMarkers ? "Hide segment markers" : "Show segment markers")
                .help("Toggle segment markers")
            }

            if showSegmentMarkers {
                SegmentMarkersView(items: generation.batchItems)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 12)
    }

    private var transportControls: some View {
        HStack(spacing: 12) {
            Button(action: {
                playback.skipBackward()
            }) {
                Label("Skip backward 10 seconds", systemImage: "gobackward.10")
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.hasGeneratedAudio)
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .accessibilityLabel("Skip backward 10 seconds")
            .help("Skip backward 10 seconds (⌘←)")

            Button(action: {
                playback.togglePlayPause()
            }) {
                Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.hasGeneratedAudio)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            .help("Play or pause (Space)")

            Button(action: {
                playback.skipForward()
            }) {
                Label("Skip forward 10 seconds", systemImage: "goforward.10")
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.hasGeneratedAudio)
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .accessibilityLabel("Skip forward 10 seconds")
            .help("Skip forward 10 seconds (⌘→)")

            Button(action: playback.stop) {
                Label("Stop", systemImage: "stop.circle")
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.hasGeneratedAudio || !playback.isPlaying)
            .keyboardShortcut(".", modifiers: .command)
            .accessibilityLabel("Stop")
            .help("Stop playback (⌘.)")
        }
    }

    private var timeline: some View {
        HStack(spacing: 10) {
            Text(formatTime(isScrubbing ? temporaryTime : playback.currentTime))
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 60, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { min(max(isScrubbing ? temporaryTime : playback.currentTime, 0), timelineDuration) },
                    set: { temporaryTime = min(max($0, 0), timelineDuration) }
                ),
                in: 0...timelineDuration
            ) { editing in
                isScrubbing = editing
                if !editing {
                    playback.seek(to: temporaryTime)
                }
            }
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(formatTime(isScrubbing ? temporaryTime : playback.currentTime)) of \(formatTime(playback.duration))")
            .disabled(!viewModel.hasGeneratedAudio || playback.duration <= 0)

            Text(formatTime(playback.duration))
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 60, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var loopToggle: some View {
        Button {
            playback.isLoopEnabled.toggle()
            settings.saveSettings()
        } label: {
            Label("Loop playback", systemImage: playback.isLoopEnabled ? "repeat.circle.fill" : "repeat")
                .labelStyle(.iconOnly)
                .imageScale(.large)
                .foregroundColor(playback.isLoopEnabled ? .accentColor : .secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Loop playback")
        .accessibilityValue(playback.isLoopEnabled ? "On" : "Off")
        .help("Toggle loop playback")
    }

    private var speedPicker: some View {
        Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                Button("\(speed, specifier: "%.2g")×") {
                    playback.playbackSpeed = speed
                    playback.applyPlaybackSpeed(save: true)
                }
            }
        } label: {
            Label("\(playback.playbackSpeed, specifier: "%.2g")×", systemImage: "speedometer")
                .labelStyle(.titleAndIcon)
        }
        .help("Playback speed")
    }

    private var volumeSlider: some View {
        HStack(spacing: 8) {
            Button {
                if playback.volume > 0 {
                    playback.volume = 0
                } else {
                    playback.volume = 0.75
                }
                playback.applyPlaybackVolume(save: true)
            } label: {
                Label(playback.volume == 0 ? "Unmute" : "Mute", systemImage: volumeIcon)
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(playback.volume == 0 ? "Unmute" : "Mute")
            .help("Toggle mute")

            Slider(value: Binding(
                get: { playback.volume },
                set: { newValue in
                    playback.volume = newValue
                    playback.applyPlaybackVolume()
                }
            ), in: 0...1) { editing in
                if !editing {
                    playback.applyPlaybackVolume(save: true)
                }
            }
            .frame(width: 120)
            .accessibilityLabel("Volume")
            .accessibilityValue("\(Int(playback.volume * 100)) percent")
        }
    }

    private var timelineDuration: Double {
        max(playback.duration, 0.01)
    }

    private var volumeIcon: String {
        if playback.volume == 0 {
            return "speaker.slash.fill"
        } else if playback.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if playback.volume < 0.66 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN && !time.isInfinite else { return "0:00" }
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

}

// MARK: - Segment Markers View

struct SegmentMarkersView: View {
    let items: [BatchGenerationItem]

    var body: some View {
        if items.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundColor(.secondary)
                Text("No queued segments. Add --- between paragraphs to prepare a batch.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(for: item.status))
                                .frame(width: 40, height: 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            Text("\(item.index)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.windowBackgroundColor))
                        )
                        .help(statusText(for: item))
                    }
                }
            }
        }
    }

    private func color(for status: BatchGenerationItem.Status) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .inProgress:
            return .accentColor
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private func statusText(for item: BatchGenerationItem) -> String {
        switch item.status {
        case .pending:
            return "Segment \(item.index) pending"
        case .inProgress:
            return "Segment \(item.index) in progress"
        case .completed:
            return "Segment \(item.index) completed"
        case .failed(let message):
            return "Segment \(item.index) failed: \(message)"
        }
    }
}
