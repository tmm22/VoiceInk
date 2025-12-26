import Foundation
import FluidAudio
import AppKit
import os

/// Provider for managing Parakeet transcription models
///
/// This class handles the lifecycle of Parakeet models including:
/// - Downloading models via FluidAudio's AsrModels
/// - Tracking download progress
/// - Deleting models from disk
///
/// - Note: This class is `@MainActor` to ensure thread-safe access to
///   published properties and UI updates.
@MainActor
final class ParakeetModelProvider: ObservableObject, ModelProviderProtocol {
    typealias ModelType = ParakeetModel
    
    // MARK: - Published Properties
    
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadStates: [String: Bool] = [:]
    
    // MARK: - Properties
    
    let providerType: ModelProvider = .parakeet
    
    /// Parakeet models use FluidAudio's cache directory, not a custom one
    var modelsDirectory: URL {
        // Return the default cache directory for v3 models
        AsrModels.defaultCacheDirectory(for: .v3)
    }
    
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "ParakeetModelProvider")
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Private Helpers
    
    private func defaultsKey(for modelName: String) -> String {
        "ParakeetModelDownloaded_\(modelName)"
    }
    
    private func version(for modelName: String) -> AsrModelVersion {
        modelName.lowercased().contains("v2") ? .v2 : .v3
    }
    
    private func cacheDirectory(for version: AsrModelVersion) -> URL {
        AsrModels.defaultCacheDirectory(for: version)
    }
    
    // MARK: - ModelProviderProtocol
    
    func isModelDownloaded(_ model: ParakeetModel) -> Bool {
        AppSettings.bool(forKey: defaultsKey(for: model.name), default: false)
    }
    
    func isModelDownloading(_ model: ParakeetModel) -> Bool {
        downloadStates[model.name] ?? false
    }
    
    func availableModels() -> [ParakeetModel] {
        // Return all predefined Parakeet models
        PredefinedModels.models.compactMap { $0 as? ParakeetModel }
    }
    
    func showModelInFinder(_ model: ParakeetModel) {
        let cacheDir = cacheDirectory(for: version(for: model.name))
        
        if FileManager.default.fileExists(atPath: cacheDir.path) {
            NSWorkspace.shared.selectFile(cacheDir.path, inFileViewerRootedAtPath: "")
        }
    }
    
    // MARK: - Model Download
    
    /// Download a Parakeet model
    /// - Parameter model: The model to download
    func downloadModel(_ model: ParakeetModel) async throws {
        if isModelDownloaded(model) {
            return
        }

        let modelName = model.name
        downloadStates[modelName] = true
        downloadProgress[modelName] = 0.0

        // Create a timer to simulate progress since FluidAudio doesn't provide progress callbacks
        let timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { 
                    timer.invalidate()
                    return 
                }
                if let currentProgress = self.downloadProgress[modelName], currentProgress < 0.9 {
                    self.downloadProgress[modelName] = currentProgress + 0.005
                }
            }
        }

        let modelVersion = version(for: modelName)

        do {
            _ = try await AsrModels.downloadAndLoad(version: modelVersion)
            _ = try await VadManager()

            AppSettings.setValue(true, forKey: defaultsKey(for: modelName))
            downloadProgress[modelName] = 1.0
        } catch {
            AppSettings.setValue(false, forKey: defaultsKey(for: modelName))
            logger.error("Failed to download Parakeet model \(modelName): \(error.localizedDescription)")
            throw error
        }

        timer.invalidate()
        downloadStates[modelName] = false
        downloadProgress[modelName] = nil
    }
    
    // MARK: - Model Deletion
    
    /// Delete a Parakeet model
    /// - Parameter model: The model to delete
    func deleteModel(_ model: ParakeetModel) async throws {
        let modelVersion = version(for: model.name)
        let cacheDir = cacheDirectory(for: modelVersion)

        if FileManager.default.fileExists(atPath: cacheDir.path) {
            try FileManager.default.removeItem(at: cacheDir)
        }
        AppSettings.setValue(false, forKey: defaultsKey(for: model.name))
    }
}
