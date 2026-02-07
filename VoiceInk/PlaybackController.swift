import AppKit
import Combine
import Foundation
import SwiftUI
import MediaRemoteAdapter

@MainActor
class PlaybackController: ObservableObject {
    static let shared = PlaybackController()
    private var mediaController: MediaRemoteAdapter.MediaController
    private var wasPlayingWhenRecordingStarted = false
    private var isMediaPlaying = false
    private var lastKnownTrackInfo: TrackInfo?
    private var originalMediaAppBundleId: String?
    private var resumeTask: Task<Void, Never>?

    
    @Published var isPauseMediaEnabled: Bool = AppSettings.Audio.isPauseMediaEnabled {
        didSet {
            AppSettings.Audio.isPauseMediaEnabled = isPauseMediaEnabled
            
            if isPauseMediaEnabled {
                startMediaTracking()
            } else {
                stopMediaTracking()
            }
        }
    }
    
    private init() {
        mediaController = MediaRemoteAdapter.MediaController()
        
        if !AppSettings.contains(key: AppSettings.Keys.isPauseMediaEnabled) {
            AppSettings.Audio.isPauseMediaEnabled = false
        }
        
        setupMediaControllerCallbacks()

        if isPauseMediaEnabled {
            startMediaTracking()
        }
    }
    
    private func setupMediaControllerCallbacks() {
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            guard let trackInfo = trackInfo else { return }
            self?.isMediaPlaying = trackInfo.payload.isPlaying ?? false
            self?.lastKnownTrackInfo = trackInfo
        }
        
        mediaController.onListenerTerminated = { }
    }
    
    deinit {
        mediaController.stopListening()
        mediaController.onTrackInfoReceived = nil
        mediaController.onListenerTerminated = nil
    }
    
    private func startMediaTracking() {
        mediaController.startListening()
    }
    
    private func stopMediaTracking() {
        mediaController.stopListening()
        isMediaPlaying = false
        lastKnownTrackInfo = nil
        wasPlayingWhenRecordingStarted = false
        originalMediaAppBundleId = nil
    }
    
    func pauseMedia() async {
        resumeTask?.cancel()
        resumeTask = nil

        wasPlayingWhenRecordingStarted = false
        originalMediaAppBundleId = nil

        guard isPauseMediaEnabled,
              isMediaPlaying,
              lastKnownTrackInfo?.payload.isPlaying == true,
              let bundleId = lastKnownTrackInfo?.payload.bundleIdentifier else {
            return
        }

        wasPlayingWhenRecordingStarted = true
        originalMediaAppBundleId = bundleId

        try? await Task.sleep(nanoseconds: 50_000_000)

        mediaController.pause()
    }

    func resumeMedia() async {
        let shouldResume = wasPlayingWhenRecordingStarted
        let originalBundleId = originalMediaAppBundleId
        let delay = MediaController.shared.audioResumptionDelay

        defer {
            wasPlayingWhenRecordingStarted = false
            originalMediaAppBundleId = nil
        }

        guard isPauseMediaEnabled,
              shouldResume,
              let bundleId = originalBundleId else {
            return
        }

        guard isAppStillRunning(bundleId: bundleId) else {
            return
        }

        guard let currentTrackInfo = lastKnownTrackInfo,
              let currentBundleId = currentTrackInfo.payload.bundleIdentifier,
              currentBundleId == bundleId,
              currentTrackInfo.payload.isPlaying == false else {
            return
        }

        let task = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            if Task.isCancelled {
                return
            }

            mediaController.play()
        }

        resumeTask = task
        await task.value
    }
    
    private func isAppStillRunning(bundleId: String) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == bundleId }
    }
}

extension UserDefaults {
    var isPauseMediaEnabled: Bool {
        get { AppSettings.Audio.isPauseMediaEnabled }
        set { AppSettings.Audio.isPauseMediaEnabled = newValue }
    }
} 
