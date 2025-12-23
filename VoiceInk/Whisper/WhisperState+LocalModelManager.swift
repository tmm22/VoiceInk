import Foundation
import os
import Zip
import Atomics


struct WhisperModel: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    var coreMLEncoderURL: URL? // Path to the unzipped .mlmodelc directory
    var isCoreMLDownloaded: Bool { coreMLEncoderURL != nil }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }
    
    var downloadURL: String {
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)"
    }
    
    var filename: String {
        "\(name).bin"
    }
    
    // Core ML related properties
    var coreMLZipDownloadURL: String? {
        guard fileExtension == "bin" else { return nil }
        guard !name.contains("q5") && !name.contains("q8") else { return nil }
        return "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(name)-encoder.mlmodelc.zip"
    }
    
    var coreMLEncoderDirectoryName: String? {
        guard coreMLZipDownloadURL != nil else { return nil }
        return "\(name)-encoder.mlmodelc"
    }
}

private class TaskDelegate: NSObject, URLSessionTaskDelegate {
    private let continuation: CheckedContinuation<Void, Never>
    private let finished = ManagedAtomic(false)

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Ensure continuation is resumed only once, even if called multiple times
        if finished.exchange(true, ordering: .acquiring) == false {
            continuation.resume()
        }
    }
}

// MARK: - Model Management Extension
extension WhisperState {

    
    
    // MARK: - Model Directory Management
    
    func createModelsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logError("Error creating models directory", error)
        }
    }

    func createFastConformerDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: fastConformerModelsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logError("Error creating FastConformer directory", error)
        }
    }

    func createSenseVoiceDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: senseVoiceModelsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logError("Error creating SenseVoice directory", error)
        }
    }
    
    func loadAvailableModels() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)
            let localModels = PredefinedModels.models.compactMap { $0 as? LocalModel }
            var filenameLookup: [String: String] = [:]
            for model in localModels {
                filenameLookup[model.filename] = model.name
            }

            availableModels = fileURLs.compactMap { url in
                let ext = url.pathExtension.lowercased()
                guard ext == "bin" || ext == "gguf" else { return nil }
                let canonicalName = filenameLookup[url.lastPathComponent] ?? url.deletingPathExtension().lastPathComponent
                return WhisperModel(name: canonicalName, url: url)
            }
        } catch {
            logError("Error loading available models", error)
        }
    }
    
    // MARK: - Model Loading
    
    func loadModel(_ model: WhisperModel) async throws {
        if let loadedModel = loadedLocalModel,
           loadedModel.name == model.name,
           whisperContext != nil {
            return
        }

        if whisperContext != nil {
            await cleanupModelResources()
        }
        
        isModelLoading = true
        defer { isModelLoading = false }
        
        do {
            whisperContext = try await WhisperContext.createContext(path: model.url.path)
            
            // Set the prompt from UserDefaults to ensure we have the latest
            let currentPrompt = AppSettings.TranscriptionSettings.prompt ?? whisperPrompt.transcriptionPrompt
            await whisperContext?.setPrompt(currentPrompt)
            
            isModelLoaded = true
            loadedLocalModel = model
        } catch {
            throw WhisperStateError.modelLoadFailed
        }
    }
    
    // MARK: - Model Download & Management
    
    /// Helper function to download a file from a URL with progress tracking
    func downloadFileWithProgress(from url: URL, to destinationURL: URL, progressKey: String, progressUpdate: ((Double) -> Void)? = nil) async throws {
        let temporaryURL = destinationURL.appendingPathExtension("download")

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Guard to prevent double resume
            let finished = ManagedAtomic(false)

            func finishOnce(_ result: Result<Void, Error>) {
                if finished.exchange(true, ordering: .acquiring) == false {
                    continuation.resume(with: result)
                }
            }

            let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                if let error = error {
                    finishOnce(.failure(error))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let tempURL = tempURL else {
                    finishOnce(.failure(URLError(.badServerResponse)))
                    return
                }

                do {
                    if FileManager.default.fileExists(atPath: temporaryURL.path) {
                        try FileManager.default.removeItem(at: temporaryURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: temporaryURL)

                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
                    finishOnce(.success(()))
                } catch {
                    finishOnce(.failure(error))
                }
            }

            task.resume()

            var lastUpdateTime = Date()
            var lastProgressValue: Double = 0

            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                let currentTime = Date()
                let timeSinceLastUpdate = currentTime.timeIntervalSince(lastUpdateTime)
                let currentProgress = round(progress.fractionCompleted * 100) / 100

                if timeSinceLastUpdate >= 0.5 && abs(currentProgress - lastProgressValue) >= 0.01 {
                    lastUpdateTime = currentTime
                    lastProgressValue = currentProgress

                    Task { @MainActor [weak self] in
                        self?.downloadProgress[progressKey] = currentProgress
                        progressUpdate?(currentProgress)
                    }
                }
            }

            Task {
                await withTaskCancellationHandler(operation: {
                    await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
                }, onCancel: {
                    observation.invalidate()
                    // Also ensure continuation is resumed with cancellation if task is cancelled
                    if finished.exchange(true, ordering: .acquiring) == false {
                        continuation.resume(throwing: CancellationError())
                    }
                })
            }
        }
    }
    func downloadModel(_ model: LocalModel) async {
        guard let url = URL(string: model.downloadURL) else { return }
        await performModelDownload(model, url)
    }
    
    private func performModelDownload(_ model: LocalModel, _ url: URL) async {
        do {
            var whisperModel = try await downloadMainModel(model, from: url)
            
            if let coreMLZipURL = whisperModel.coreMLZipDownloadURL,
               let coreMLURL = URL(string: coreMLZipURL) {
                whisperModel = try await downloadAndSetupCoreMLModel(for: whisperModel, from: coreMLURL)
            }
            
            availableModels.append(whisperModel)
            self.downloadProgress.removeValue(forKey: model.name + "_main")

            if shouldWarmup(model) {
                WhisperModelWarmupCoordinator.shared.scheduleWarmup(for: model, whisperState: self)
            }
        } catch {
            handleModelDownloadError(model, error)
        }
    }
    
    private func downloadMainModel(_ model: LocalModel, from url: URL) async throws -> WhisperModel {
        let progressKeyMain = model.name + "_main"
        let destinationURL = modelsDirectory.appendingPathComponent(model.filename)
        try await downloadFileWithProgress(from: url, to: destinationURL, progressKey: progressKeyMain)
        
        return WhisperModel(name: model.name, url: destinationURL)
    }
    
    private func downloadAndSetupCoreMLModel(for model: WhisperModel, from url: URL) async throws -> WhisperModel {
        let progressKeyCoreML = model.name + "_coreml"
        let coreMLZipPath = modelsDirectory.appendingPathComponent("\(model.name)-encoder.mlmodelc.zip")
        try await downloadFileWithProgress(from: url, to: coreMLZipPath, progressKey: progressKeyCoreML)
        
        return try await unzipAndSetupCoreMLModel(for: model, zipPath: coreMLZipPath, progressKey: progressKeyCoreML)
    }
    
    private func unzipAndSetupCoreMLModel(for model: WhisperModel, zipPath: URL, progressKey: String) async throws -> WhisperModel {
        let coreMLDestination = modelsDirectory.appendingPathComponent("\(model.name)-encoder.mlmodelc")
        
        // Best-effort cleanup; previous CoreML artifacts may not exist.
        try? FileManager.default.removeItem(at: coreMLDestination)
        try await unzipCoreMLFile(zipPath, to: modelsDirectory)
        return try verifyAndCleanupCoreMLFiles(model, coreMLDestination, zipPath, progressKey)
    }
    
    private func unzipCoreMLFile(_ zipPath: URL, to destination: URL) async throws {
        let finished = ManagedAtomic(false)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            func finishOnce(_ result: Result<Void, Error>) {
                if finished.exchange(true, ordering: .acquiring) == false {
                    continuation.resume(with: result)
                }
            }

            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try Zip.unzipFile(zipPath, destination: destination, overwrite: true, password: nil)
                finishOnce(.success(()))
            } catch {
                finishOnce(.failure(error))
            }
        }
    }
    
    private func verifyAndCleanupCoreMLFiles(_ model: WhisperModel, _ destination: URL, _ zipPath: URL, _ progressKey: String) throws -> WhisperModel {
        var model = model
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            // Best-effort cleanup; zip may already be removed.
            try? FileManager.default.removeItem(at: zipPath)
            throw WhisperStateError.unzipFailed
        }
        
        // Best-effort cleanup; zip may already be removed.
        try? FileManager.default.removeItem(at: zipPath)
        model.coreMLEncoderURL = destination
        self.downloadProgress.removeValue(forKey: progressKey)
        
        return model
    }

    private func shouldWarmup(_ model: LocalModel) -> Bool {
        model.fileExtension == "bin" && !model.name.contains("q5") && !model.name.contains("q8")
    }
    
    private func handleModelDownloadError(_ model: LocalModel, _ error: Error) {
        self.downloadProgress.removeValue(forKey: model.name + "_main")
        self.downloadProgress.removeValue(forKey: model.name + "_coreml")
        logger.error("Model download failed for \(model.displayName): \(error.localizedDescription)")
        NotificationManager.shared.showNotification(
            title: String(format: Localization.Models.downloadFailedForModel, model.displayName),
            type: .error
        )
    }
    
    func deleteModel(_ model: WhisperModel) async {
        do {
            // Delete main model file
            try FileManager.default.removeItem(at: model.url)
            
            // Delete CoreML model if it exists
            if let coreMLURL = model.coreMLEncoderURL {
                // Best-effort cleanup; file may already be removed.
                try? FileManager.default.removeItem(at: coreMLURL)
            } else {
                // Check if there's a CoreML directory matching the model name
                let coreMLDir = modelsDirectory.appendingPathComponent("\(model.name)-encoder.mlmodelc")
                if FileManager.default.fileExists(atPath: coreMLDir.path) {
                    // Best-effort cleanup; directory may already be removed.
                    try? FileManager.default.removeItem(at: coreMLDir)
                }
            }
            
            // Update model state
            availableModels.removeAll { $0.id == model.id }
            if currentTranscriptionModel?.name == model.name {

                currentTranscriptionModel = nil
                AppSettings.TranscriptionSettings.currentTranscriptionModel = nil

                loadedLocalModel = nil
                recordingState = .idle
                AppSettings.TranscriptionSettings.currentModel = nil
            }
        } catch {
            logError("Error deleting model: \(model.name)", error)
        }

        // Ensure UI reflects removal of imported models as well
        // No need for MainActor.run - WhisperState is already @MainActor
        self.refreshAllAvailableModels()
    }
    
    func unloadModel() {
        Task {
            await whisperContext?.releaseResources()
            whisperContext = nil
            isModelLoaded = false
            
            if let recordedFile = recordedFile {
                // Best-effort cleanup; recording may already be removed.
                try? FileManager.default.removeItem(at: recordedFile)
                self.recordedFile = nil
            }
        }
    }
    
    func clearDownloadedModels() async {
        for model in availableModels {
            do {
                try FileManager.default.removeItem(at: model.url)
            } catch {
                logError("Error deleting model during cleanup", error)
            }
        }
        availableModels.removeAll()
    }
    
    // MARK: - Resource Management
    
    func cleanupModelResources() async {
        await whisperContext?.releaseResources()
        whisperContext = nil
        isModelLoaded = false

        parakeetTranscriptionService.cleanup()
        fastConformerTranscriptionService.cleanup()
        senseVoiceTranscriptionService.cleanup()
    }
    
    // MARK: - Helper Methods
    
    private func logError(_ message: String, _ error: Error) {
        self.logger.error("\(message): \(error.localizedDescription)")
    }

    // MARK: - Import Local Model (User-provided .bin)

    @MainActor
    func importLocalModel(from sourceURL: URL) async {
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard ["bin", "gguf"].contains(fileExtension) else { return }

        // Build a destination URL inside the app-managed models directory
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let destinationURL = modelsDirectory.appendingPathComponent("\(baseName).\(fileExtension)")

        // Do not rename on collision; simply notify the user and abort
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            NotificationManager.shared.showNotification(
                title: String(format: Localization.Models.modelExists, destinationURL.lastPathComponent),
                type: .warning,
                duration: 4.0
            )
            return
        }

        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            // Append ONLY the newly imported model to in-memory lists (no full rescan)
            let newWhisperModel = WhisperModel(name: baseName, url: destinationURL)
            availableModels.append(newWhisperModel)

            if !allAvailableModels.contains(where: { $0.name == baseName }) {
                let imported = ImportedLocalModel(fileBaseName: baseName)
                allAvailableModels.append(imported)
            }

            NotificationManager.shared.showNotification(
                title: String(format: Localization.Models.importSuccess, destinationURL.lastPathComponent),
                type: .success,
                duration: 3.0
            )
        } catch {
            logError("Failed to import local model", error)
            NotificationManager.shared.showNotification(
                title: String(format: Localization.Models.importFailed, error.localizedDescription),
                type: .error,
                duration: 5.0
            )
        }
    }
}
