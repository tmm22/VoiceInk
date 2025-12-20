import AppKit
import Combine
import Foundation
import SwiftUI
import CoreAudio

/// Controls system audio management during recording
@MainActor
class MediaController: ObservableObject {
    static let shared = MediaController()
    private var didMuteAudio = false
    private var wasAudioMutedBeforeRecording = false
    private var currentMuteTask: Task<Bool, Never>?
    
    @Published var isSystemMuteEnabled: Bool = UserDefaults.standard.bool(forKey: "isSystemMuteEnabled") {
        didSet {
            UserDefaults.standard.set(isSystemMuteEnabled, forKey: "isSystemMuteEnabled")
        }
    }
    
    private init() {
        // Set default if not already set
        if !UserDefaults.standard.contains(key: "isSystemMuteEnabled") {
            UserDefaults.standard.set(true, forKey: "isSystemMuteEnabled")
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

extension UserDefaults {
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
    
    var isSystemMuteEnabled: Bool {
        get { bool(forKey: "isSystemMuteEnabled") }
        set { set(newValue, forKey: "isSystemMuteEnabled") }
    }
}
