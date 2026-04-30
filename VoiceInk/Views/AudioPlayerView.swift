import SwiftUI
import AppKit

struct AudioPlayerView: View {
    let url: URL
    @StateObject private var playerManager = AudioPlayerManager()
    @State private var isHovering = false
    @State private var isRetranscribing = false
    @State private var showRetranscribeSuccess = false
    @State private var showRetranscribeError = false
    @State private var errorMessage = ""
    @State private var showPromptPopover = false
    @EnvironmentObject private var whisperState: WhisperState
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext

    private var transcriptionService: AudioTranscriptionService {
        AudioTranscriptionService(modelContext: modelContext, whisperState: whisperState)
    }

    var body: some View {
        VStack(spacing: 8) {
            WaveformView(
                samples: playerManager.waveformSamples,
                currentTime: playerManager.currentTime,
                duration: playerManager.duration,
                isLoading: playerManager.isLoadingWaveform,
                onSeek: { playerManager.seek(to: $0) }
            )
            .padding(.horizontal, 10)

            HStack(spacing: 8) {
                Text(formatTime(playerManager.currentTime))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)

                Spacer()

                transportControls

                Spacer()

                Text(formatTime(playerManager.duration))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .onAppear {
            playerManager.loadAudio(from: url)
        }
        .onDisappear {
            playerManager.cleanup()
        }
        .overlay(statusOverlay)
    }

    private var transportControls: some View {
        HStack(spacing: 8) {
            circularControl(systemImage: "folder", action: showInFinder)
                .help("Show in Finder")

            Button(action: togglePlayback) {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .contentTransition(.symbolEffect(.replace.downUp))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playerManager.isPlaying ? "Pause audio" : "Play audio")
            .help(playerManager.isPlaying ? "Pause audio" : "Play audio")
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .onHover { hovering in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isHovering = hovering
                }
            }

            Button(action: { showPromptPopover.toggle() }) {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: enhancementService.activePrompt?.icon ?? "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    )
            }
            .buttonStyle(.plain)
            .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.4)
            .accessibilityLabel("Select enhancement prompt")
            .help("Select enhancement prompt")
            .popover(isPresented: $showPromptPopover, arrowEdge: .bottom) {
                EnhancementPromptPopover()
                    .environmentObject(enhancementService)
            }

            Button(action: retranscribeAudio) {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 32, height: 32)
                    .overlay(retranscriptionIndicator)
            }
            .buttonStyle(.plain)
            .disabled(isRetranscribing)
            .accessibilityLabel(isRetranscribing ? "Retranscribing audio" : "Retranscribe this audio")
            .help("Retranscribe this audio")
        }
    }

    private var retranscriptionIndicator: some View {
        Group {
            if isRetranscribing {
                ProgressView()
                    .controlSize(.small)
            } else if showRetranscribeSuccess {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.green)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var statusOverlay: some View {
        VStack {
            if showRetranscribeSuccess {
                statusBanner(
                    systemImage: "checkmark.circle.fill",
                    message: "Retranscription successful",
                    tint: .green
                )
            }

            if showRetranscribeError {
                statusBanner(
                    systemImage: "exclamationmark.circle.fill",
                    message: errorMessage.isEmpty ? "Retranscription failed" : errorMessage,
                    tint: .red
                )
            }

            Spacer()
        }
        .padding(.top, 16)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showRetranscribeSuccess)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showRetranscribeError)
    }

    private func circularControl(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemImage == "folder" ? "Show audio file in Finder" : systemImage)
    }

    private func statusBanner(systemImage: String, message: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(tint)
            Text(message)
                .font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func showInFinder() {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    private func togglePlayback() {
        if playerManager.isPlaying {
            playerManager.pause()
        } else {
            playerManager.play()
        }
    }

    private func retranscribeAudio() {
        guard let currentTranscriptionModel = whisperState.currentTranscriptionModel else {
            errorMessage = "No transcription model selected"
            showRetranscribeError = true
            scheduleErrorReset()
            return
        }

        isRetranscribing = true

        Task {
            do {
                _ = try await transcriptionService.retranscribeAudio(from: url, using: currentTranscriptionModel)
                await MainActor.run {
                    isRetranscribing = false
                    showRetranscribeSuccess = true
                }
                scheduleSuccessReset()
            } catch {
                await MainActor.run {
                    isRetranscribing = false
                    errorMessage = error.localizedDescription
                    showRetranscribeError = true
                }
                scheduleErrorReset()
            }
        }
    }

    private func scheduleSuccessReset() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation {
                showRetranscribeSuccess = false
            }
        }
    }

    private func scheduleErrorReset() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation {
                showRetranscribeError = false
            }
        }
    }
}
