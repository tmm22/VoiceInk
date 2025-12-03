import SwiftUI
import AVFoundation

// MARK: - Audio Playback Controls
extension TTSViewModel {
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