import SwiftUI
import AVFoundation
import Combine

// MARK: - Audio Playback Setup & Controls
extension TTSViewModel {
    
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

        // Handle loop mode
        audioPlayer.didFinishPlaying = { [weak self] in
            guard let self = self else { return }
            if self.isLoopEnabled {
                Task {
                    await self.play()
                }
            }
        }
    }

    func setupPreviewPlayer() {
        previewPlayer.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                guard let self else { return }
                self.isPreviewing = playing && self.previewingVoiceID != nil
            }
            .store(in: &cancellables)

        previewPlayer.$isBuffering
            .receive(on: DispatchQueue.main)
            .sink { [weak self] buffering in
                guard let self else { return }
                if self.previewingVoiceID == nil {
                    self.isPreviewLoading = false
                } else {
                    self.isPreviewLoading = buffering
                }
            }
            .store(in: &cancellables)

        previewPlayer.$error
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.handlePreviewError(error, voiceName: nil)
            }
            .store(in: &cancellables)

        previewPlayer.didFinishPlaying = { [weak self] in
            guard let self else { return }
            self.resetPreviewState()
        }
    }
    
    // MARK: - Playback Controls
    
    func play() async {
        stopPreview()
        applyPlaybackSettings()
        audioPlayer.play()
        isPlaying = true
    }

    func pause() {
        audioPlayer.pause()
        isPlaying = false
    }

    func stop() {
        stopPreview()
        audioPlayer.stop()
        isPlaying = false
        currentTime = 0
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            Task {
                await play()
            }
        }
    }

    func applyPlaybackSpeed(save: Bool = false) {
        let clamped = min(max(playbackSpeed, 0.5), 2.0)
        if abs(playbackSpeed - clamped) > styleComparisonEpsilon {
            playbackSpeed = clamped
        }
        audioPlayer.setPlaybackRate(Float(clamped))

        if save {
            saveSettings()
        }
    }

    func applyPlaybackVolume(save: Bool = false) {
        let clamped = min(max(volume, 0.0), 1.0)
        if abs(volume - clamped) > styleComparisonEpsilon {
            volume = clamped
        }
        audioPlayer.setVolume(Float(clamped))

        if save {
            saveSettings()
        }
    }

    func applyPlaybackSettings(save: Bool = false) {
        applyPlaybackSpeed()
        applyPlaybackVolume()

        if save {
            saveSettings()
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