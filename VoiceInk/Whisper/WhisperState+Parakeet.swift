import Foundation
import FluidAudio
import AppKit

extension WhisperState {
    var isParakeetModelDownloaded: Bool {
        get { UserDefaults.standard.bool(forKey: "ParakeetModelDownloaded") }
        set { UserDefaults.standard.set(newValue, forKey: "ParakeetModelDownloaded") }
    }

    var isParakeetModelDownloading: Bool {
        get { isDownloadingParakeet }
        set { isDownloadingParakeet = newValue }
    }

    @MainActor
    func downloadParakeetModel() async {
        if isParakeetModelDownloaded {
            return
        }

        isDownloadingParakeet = true
        downloadProgress["parakeet-tdt-0.6b"] = 0.0

        // Start progress simulation
        let timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { timer in
            Task { @MainActor in
                if let currentProgress = self.downloadProgress["parakeet-tdt-0.6b"], currentProgress < 0.9 {
                    self.downloadProgress["parakeet-tdt-0.6b"] = currentProgress + 0.0125
                }
            }
        }

        do {
            _ = try await AsrModels.downloadAndLoad(to: parakeetModelsDirectory)

            // Also download VAD model into the same parent directory as ASR models
            let parentDir = parakeetModelsDirectory.deletingLastPathComponent()
            _ = try await DownloadUtils.loadModels(
                .vad,
                modelNames: Array(ModelNames.VAD.requiredModels),
                directory: parentDir
            )
            self.isParakeetModelDownloaded = true
            downloadProgress["parakeet-tdt-0.6b"] = 1.0
        } catch {
            self.isParakeetModelDownloaded = false
        }
        
        timer.invalidate()
        isDownloadingParakeet = false
        downloadProgress["parakeet-tdt-0.6b"] = nil
        
        refreshAllAvailableModels()
    }
    
    @MainActor
    func deleteParakeetModel() {
        if let currentModel = currentTranscriptionModel, currentModel.provider == .parakeet {
            currentTranscriptionModel = nil
            UserDefaults.standard.removeObject(forKey: "CurrentTranscriptionModel")
        }
        
        do {
            // First try: app support directory + bundle path
            let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.prakashjoshipax.VoiceInk")
            let parakeetModelDirectory = appSupportDirectory.appendingPathComponent("parakeet-tdt-0.6b-v3-coreml")
            
            if FileManager.default.fileExists(atPath: parakeetModelDirectory.path) {
                try FileManager.default.removeItem(at: parakeetModelDirectory)
            } else {
                // Second try: root of application support directory
                let rootAppSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                let rootParakeetModelDirectory = rootAppSupportDirectory.appendingPathComponent("parakeet-tdt-0.6b-v3-coreml")
                
                if FileManager.default.fileExists(atPath: rootParakeetModelDirectory.path) {
                    try FileManager.default.removeItem(at: rootParakeetModelDirectory)
                }
            }
            
            self.isParakeetModelDownloaded = false
            
        } catch {
            // Silently fail
        }
        
        refreshAllAvailableModels()
    }
    
    @MainActor
    func showParakeetModelInFinder() {
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
        let parakeetModelDirectory = appSupportDirectory.appendingPathComponent("parakeet-tdt-0.6b-v3-coreml")
        
        if FileManager.default.fileExists(atPath: parakeetModelDirectory.path) {
            NSWorkspace.shared.selectFile(parakeetModelDirectory.path, inFileViewerRootedAtPath: "")
        }
    }
} 
