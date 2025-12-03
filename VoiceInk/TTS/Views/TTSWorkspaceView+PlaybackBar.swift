import SwiftUI
import AppKit

// MARK: - Playback Bar View

struct PlaybackBarView: View {
    @EnvironmentObject var viewModel: TTSViewModel
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
                    Image(systemName: showSegmentMarkers ? "chevron.down.circle" : "chevron.up.circle")
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .help("Toggle segment markers")
            }

            if showSegmentMarkers {
                SegmentMarkersView(items: viewModel.batchItems)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 12)
    }

    private var transportControls: some View {
        HStack(spacing: 12) {
            Button(action: {
                viewModel.skipBackward()
            }) {
                Image(systemName: "gobackward.10")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.audioData == nil)
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .help("Skip backward 10 seconds (⌘←)")

            Button(action: {
                viewModel.togglePlayPause()
            }) {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.audioData == nil)
            .keyboardShortcut(.space, modifiers: [])
            .help("Play or pause (Space)")

            Button(action: {
                viewModel.skipForward()
            }) {
                Image(systemName: "goforward.10")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.audioData == nil)
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .help("Skip forward 10 seconds (⌘→)")

            Button(action: viewModel.stop) {
                Image(systemName: "stop.circle")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.audioData == nil || !viewModel.isPlaying)
            .keyboardShortcut(".", modifiers: .command)
            .help("Stop playback (⌘.)")
        }
    }

    private var timeline: some View {
        HStack(spacing: 10) {
            Text(formatTime(isScrubbing ? temporaryTime : viewModel.currentTime))
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 60, alignment: .trailing)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)

                    Capsule()
                        .fill(Color.accentColor)
                        .frame(
                            width: viewModel.duration > 0 ? geometry.size.width * CGFloat(progressValue) : 0,
                            height: 6
                        )

                    if viewModel.duration > 0 {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 14, height: 14)
                            .offset(x: geometry.size.width * CGFloat(progressValue) - 7)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        isScrubbing = true
                                        let ratio = min(max(value.location.x / geometry.size.width, 0), 1)
                                        temporaryTime = TimeInterval(ratio) * viewModel.duration
                                    }
                                    .onEnded { value in
                                        let ratio = min(max(value.location.x / geometry.size.width, 0), 1)
                                        let newTime = TimeInterval(ratio) * viewModel.duration
                                        viewModel.seek(to: newTime)
                                        isScrubbing = false
                                    }
                            )
                    }
                }
            }
            .frame(height: 18)

            Text(formatTime(viewModel.duration))
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 60, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var loopToggle: some View {
        Button {
            viewModel.isLoopEnabled.toggle()
            viewModel.saveSettings()
        } label: {
            Image(systemName: viewModel.isLoopEnabled ? "repeat.circle.fill" : "repeat")
                .imageScale(.large)
                .foregroundColor(viewModel.isLoopEnabled ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help("Toggle loop playback")
    }

    private var speedPicker: some View {
        Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                Button("\(speed, specifier: "%.2g")×") {
                    viewModel.playbackSpeed = speed
                    viewModel.applyPlaybackSpeed(save: true)
                }
            }
        } label: {
            Label("\(viewModel.playbackSpeed, specifier: "%.2g")×", systemImage: "speedometer")
                .labelStyle(.titleAndIcon)
        }
        .help("Playback speed")
    }

    private var volumeSlider: some View {
        HStack(spacing: 8) {
            Button {
                if viewModel.volume > 0 {
                    viewModel.volume = 0
                } else {
                    viewModel.volume = 0.75
                }
                viewModel.applyPlaybackVolume(save: true)
            } label: {
                Image(systemName: volumeIcon)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .help("Toggle mute")

            Slider(value: Binding(
                get: { viewModel.volume },
                set: { newValue in
                    viewModel.volume = newValue
                    viewModel.applyPlaybackVolume()
                }
            ), in: 0...1) { editing in
                if !editing {
                    viewModel.applyPlaybackVolume(save: true)
                }
            }
            .frame(width: 120)
        }
    }

    private var progressValue: Double {
        if isScrubbing {
            guard viewModel.duration > 0 else { return 0 }
            return temporaryTime / viewModel.duration
        }
        guard viewModel.duration > 0 else { return 0 }
        return viewModel.currentTime / viewModel.duration
    }

    private var volumeIcon: String {
        if viewModel.volume == 0 {
            return "speaker.slash.fill"
        } else if viewModel.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if viewModel.volume < 0.66 {
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