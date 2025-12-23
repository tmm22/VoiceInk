import Foundation
import Combine

@MainActor
final class TTSPlaybackViewModel: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackSpeed: Double = 1.0
    @Published var volume: Double = 0.75
    @Published var isLoopEnabled: Bool = false

    let audioPlayer: AudioPlayerService
    var onPersistSettings: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private let comparisonEpsilon = 0.0001

    init(audioPlayer: AudioPlayerService? = nil) {
        self.audioPlayer = audioPlayer ?? AudioPlayerService()
        setupAudioPlayer()
    }

    // MARK: - Audio Player Setup
    func setupAudioPlayer() {
        audioPlayer.$currentTime
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentTime)

        audioPlayer.$duration
            .receive(on: DispatchQueue.main)
            .assign(to: &$duration)

        audioPlayer.$isPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPlaying)

        audioPlayer.didFinishPlaying = { [weak self] in
            guard let self else { return }
            if self.isLoopEnabled {
                Task { [weak self] in
                    await self?.play()
                }
            }
        }
    }

    // MARK: - Playback Controls
    func play() async {
        applyPlaybackSettings()
        audioPlayer.play()
    }

    func pause() {
        audioPlayer.pause()
    }

    func stop() {
        audioPlayer.stop()
        currentTime = 0
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            Task { [weak self] in
                await self?.play()
            }
        }
    }

    func applyPlaybackSpeed(save: Bool = false) {
        let clamped = min(max(playbackSpeed, 0.5), 2.0)
        if abs(playbackSpeed - clamped) > comparisonEpsilon {
            playbackSpeed = clamped
        }
        audioPlayer.setPlaybackRate(Float(clamped))

        if save {
            onPersistSettings?()
        }
    }

    func applyPlaybackVolume(save: Bool = false) {
        let clamped = min(max(volume, 0.0), 1.0)
        if abs(volume - clamped) > comparisonEpsilon {
            volume = clamped
        }
        audioPlayer.setVolume(Float(clamped))

        if save {
            onPersistSettings?()
        }
    }

    func applyPlaybackSettings(save: Bool = false) {
        applyPlaybackSpeed()
        applyPlaybackVolume()

        if save {
            onPersistSettings?()
        }
    }

    func seek(to time: TimeInterval) {
        audioPlayer.seek(to: time)
        currentTime = time
    }

    func skipForward(_ seconds: TimeInterval = 10) {
        let newTime = min(duration, currentTime + seconds)
        seek(to: newTime)
    }

    func skipBackward(_ seconds: TimeInterval = 10) {
        let newTime = max(0, currentTime - seconds)
        seek(to: newTime)
    }
}
