import Foundation
import os
import Zip
import Atomics
import AppKit

/// Provider for managing local Whisper models
///
/// This class handles the lifecycle of local Whisper models including:
/// - Downloading models from Hugging Face
/// - Loading models into memory via WhisperContext
/// - Deleting models from disk
/// - Tracking download progress
///
/// - Note: This class is `@MainActor` to ensure thread-safe access to
///   published properties and UI updates.
@MainActor
final class LocalModelProvider: ObservableObject, LoadableModelProviderProtocol {
    typealias ModelType = WhisperModel
    
    // MARK: - Published Properties
    
    @Published var downloadProgress: [String: Double] = [:]
    @Published var loadedModel: WhisperModel?
    @Published var isModelLoaded = false
    @Published var isModelLoading = false
    @Published private(set) var whisperModels: [WhisperModel] = []
    
    // MARK: - Properties
    
    let providerType: ModelProvider = .local
    let modelsDirectory: URL
    
    /// The WhisperContext for the currently loaded model
    private(set) var whisperContext: WhisperContext?
    
    /// Prompt manager for transcription hints
    let whisperPrompt = WhisperPrompt()
    
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "LocalModelProvider")
    
    // MARK: - Initialization
    
    /// Initialize the provider with a models directory
    /// - Parameter modelsDirectory: Directory where models are stored
    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
        createModelsDirectoryIfNeeded()
        loadAvailableModels()
    }
    
    // MARK: - Directory Management
    
    /// Create the models directory if it doesn't exist
    func createModelsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error("Error creating models directory: \(error.localizedDescription)")
        }
    }
    
    /// Scan the models directory and load available models
    func loadAvailableModels() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)
            let localModels = PredefinedModels.models.compactMap { $0 as? LocalModel }
            var filenameLookup: [String: String] = [:]
            for model in localModels {
                filenameLookup[model.filename] = model.name
            }

            whisperModels = fileURLs.compactMap { url in
                let ext = url.pathExtension.lowercased()
                guard ext == "bin" || ext == "gguf" else { return nil }
                let canonicalName = filenameLookup[url.lastPathComponent] ?? url.deletingPathExtension().lastPathComponent
                return WhisperModel(name: canonicalName, url: url)
            }
        } catch {
            logger.error("Error loading available models: \(error.localizedDescription)")
        }
    }
    
    // MARK: - ModelProviderProtocol
    
    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        whisperModels.contains { $0.name == model.name }
    }
    
    func isModelDownloading(_ model: WhisperModel) -> Bool {
        downloadProgress[model.name + "_main"] != nil
    }
    
    func availableModels() -> [WhisperModel] {
        whisperModels
    }
    
    func showModelInFinder(_ model: WhisperModel) {
        if FileManager.default.fileExists(atPath: model.url.path) {
            NSWorkspace.shared.selectFile(model.url.path, inFileViewerRootedAtPath: "")
        }
    }
    
    // MARK: - LoadableModelProviderProtocol
    
    /// Load a Whisper model into memory
    /// - Parameter model: The model to load
    /// - Throws: `WhisperStateError.modelLoadFailed` if loading fails
    func loadModel(_ model: WhisperModel) async throws {
        // Skip if already loaded
        if let loaded = loadedModel,
           loaded.name == model.name,
           whisperContext != nil {
            return
        }

        // Unload existing model first
        if whisperContext != nil {
            await unloadModel()
        }
        
        isModelLoading = true
        defer { isModelLoading = false }
        
        do {
            whisperContext = try await WhisperContext.createContext(path: model.url.path)
            
            // Set the prompt from UserDefaults to ensure we have the latest
            let currentPrompt = AppSettings.TranscriptionSettings.prompt ?? whisperPrompt.transcriptionPrompt
            await whisperContext?.setPrompt(currentPrompt)
            
            isModelLoaded = true
            loadedModel = model
        } catch {
            throw WhisperStateError.modelLoadFailed
        }
    }
    
    /// Unload the current model from memory
    func unloadModel() async {
        await whisperContext?.releaseResources()
        whisperContext = nil
        isModelLoaded = false
        loadedModel = nil
    }
    
    // MARK: - Model Download
    
    /// Download a model from the predefined model list
    /// - Parameter model: The LocalModel definition to download
    func downloadModel(_ model: WhisperModel) async throws {
        // For WhisperModel, we need to find the corresponding LocalModel
        guard let localModel = PredefinedModels.models.first(where: { $0.name == model.name }) as? LocalModel,
              let url = URL(string: localModel.downloadURL) else {
            throw WhisperStateError.modelLoadFailed
        }
        
        try await performModelDownload(localModel, url)
    }
    
    /// Download a model from a LocalModel definition
    /// - Parameter model: The LocalModel to download
    func downloadLocalModel(_ model: LocalModel) async throws {
        guard let url = URL(string: model.downloadURL) else {
            throw WhisperStateError.modelLoadFailed
        }
        try await performModelDownload(model, url)
    }
    
    private func performModelDownload(_ model: LocalModel, _ url: URL) async throws {
        var whisperModel = try await downloadMainModel(model, from: url)
        
        if let coreMLZipURL = whisperModel.coreMLZipDownloadURL,
           let coreMLURL = URL(string: coreMLZipURL) {
            whisperModel = try await downloadAndSetupCoreMLModel(for: whisperModel, from: coreMLURL)
        }
        
        whisperModels.append(whisperModel)
        downloadProgress.removeValue(forKey: model.name + "_main")

        if shouldWarmup(model) {
            WhisperModelWarmupCoordinator.shared.scheduleWarmup(for: model, localProvider: self)
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
        downloadProgress.removeValue(forKey: progressKey)
        
        return model
    }

    private func shouldWarmup(_ model: LocalModel) -> Bool {
        model.fileExtension == "bin" && !model.name.contains("q5") && !model.name.contains("q8")
    }
    
    // MARK: - Model Deletion
    
    /// Delete a model from disk
    /// - Parameter model: The model to delete
    func deleteModel(_ model: WhisperModel) async throws {
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
        whisperModels.removeAll { $0.id == model.id }
        
        // Unload if this was the loaded model
        if loadedModel?.name == model.name {
            await unloadModel()
        }
    }
    
    /// Clear all downloaded models
    func clearDownloadedModels() async {
        for model in whisperModels {
            do {
                try FileManager.default.removeItem(at: model.url)
            } catch {
                logger.error("Error deleting model during cleanup: \(error.localizedDescription)")
            }
        }
        whisperModels.removeAll()
    }
    
    // MARK: - Resource Management
    
    /// Clean up all model resources
    func cleanupModelResources() async {
        await whisperContext?.releaseResources()
        whisperContext = nil
        isModelLoaded = false
    }
    
    // MARK: - Import Local Model
    
    /// Import a user-provided model file
    /// - Parameter sourceURL: URL of the model file to import
    /// - Returns: The imported WhisperModel, or nil if import failed
    @discardableResult
    func importLocalModel(from sourceURL: URL) async -> WhisperModel? {
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard ["bin", "gguf"].contains(fileExtension) else { return nil }

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
            return nil
        }

        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            // Append the newly imported model to in-memory list
            let newWhisperModel = WhisperModel(name: baseName, url: destinationURL)
            whisperModels.append(newWhisperModel)

            NotificationManager.shared.showNotification(
                title: String(format: Localization.Models.importSuccess, destinationURL.lastPathComponent),
                type: .success,
                duration: 3.0
            )
            
            return newWhisperModel
        } catch {
            logger.error("Failed to import local model: \(error.localizedDescription)")
            NotificationManager.shared.showNotification(
                title: String(format: Localization.Models.importFailed, error.localizedDescription),
                type: .error,
                duration: 5.0
            )
            return nil
        }
    }
    
    // MARK: - Download Helper
    
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
}
