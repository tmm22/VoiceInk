import Foundation
import CoreAudio

/// Controls system audio management during recording
@MainActor
class MediaController: ObservableObject {
    static let shared = MediaController()

    private var didMuteAudio = false
    private var wasAudioMutedBeforeRecording = false
    private var currentMuteTask: Task<Bool, Never>?
    
    @Published var isSystemMuteEnabled: Bool = AppSettings.Audio.isSystemMuteEnabled {
        didSet {
            AppSettings.Audio.isSystemMuteEnabled = isSystemMuteEnabled
        }
    }
    
    private init() {
        // Set default if not already set
        if !AppSettings.contains(key: AppSettings.Keys.isSystemMuteEnabled) {
            AppSettings.Audio.isSystemMuteEnabled = true
        }
    }
    
    /// Mutes system audio during recording
    func muteSystemAudio() async -> Bool {
        guard isSystemMuteEnabled else { return false }
        
        // Cancel any existing mute task and create a new one
        currentMuteTask?.cancel()
        
        let task = Task.detached(priority: .utility) { [weak self] in
            let wasMuted = Self.isSystemAudioMuted()
            if wasMuted {
                await self?.setMuteState(wasMutedBeforeRecording: true, didMuteAudio: false)
                return true
            }

            let success = Self.executeAppleScript(command: "set volume with output muted")
            await self?.setMuteState(wasMutedBeforeRecording: false, didMuteAudio: success)
            return success
        }
        
        currentMuteTask = task
        return await task.value
    }
    
    /// Restores system audio after recording
    func unmuteSystemAudio() async {
        guard isSystemMuteEnabled else { return }
        
        // Wait for any pending mute operation to complete first
        if let muteTask = currentMuteTask {
            _ = await muteTask.value
        }
        
        let shouldUnmute = didMuteAudio && !wasAudioMutedBeforeRecording
        didMuteAudio = false
        currentMuteTask = nil

        if shouldUnmute {
            _ = await Task.detached(priority: .utility) {
                Self.executeAppleScript(command: "set volume without output muted")
            }.value
        }
    }
    
    private func setMuteState(wasMutedBeforeRecording: Bool, didMuteAudio: Bool) {
        wasAudioMutedBeforeRecording = wasMutedBeforeRecording
        self.didMuteAudio = didMuteAudio
    }

    /// Checks if the system audio is currently muted using AppleScript
    nonisolated private static func isSystemAudioMuted() -> Bool {
        let pipe = Pipe()
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", "output muted of (get volume settings)"]
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return output == "true"
            }
        } catch {
            // Silently fail
        }
        
        return false
    }
    
    /// Executes an AppleScript command
    nonisolated private static func executeAppleScript(command: String) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", command]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}

        let delay = audioResumptionDelay
        let shouldUnmute = didMuteAudio && !wasAudioMutedBeforeRecording
        let myGeneration = muteGeneration

        let task = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard let self = self else { return }
            guard !Task.isCancelled else { return }
            guard self.muteGeneration == myGeneration else { return }

            if shouldUnmute {
                _ = self.setSystemMuted(false)
            }

            self.didMuteAudio = false
        }

        unmuteTask = task
        await task.value
    }
    
    var isSystemMuteEnabled: Bool {
        get { AppSettings.Audio.isSystemMuteEnabled }
        set { AppSettings.Audio.isSystemMuteEnabled = newValue }
    }
}
