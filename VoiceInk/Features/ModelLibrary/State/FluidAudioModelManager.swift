import AppKit
import FluidAudio
import Foundation
import os

struct FluidAudioDownloadStatus: Equatable {
    let fractionCompleted: Double
    let message: String
    let isIndeterminate: Bool

    init(fractionCompleted: Double, message: String, isIndeterminate: Bool = false) {
        self.fractionCompleted = fractionCompleted
        self.message = message
        self.isIndeterminate = isIndeterminate
    }
}

@MainActor
class FluidAudioModelManager: ObservableObject {
    @Published private var downloadStatuses: [String: FluidAudioDownloadStatus] = [:]
    @Published private var modelStateRevision = 0
    private var activeDownloadIDs: [String: UUID] = [:]
    private var activeNetworkProgressIDs: [String: UUID] = [:]
    private var activeDownloadTasks: [String: Task<Void, Never>] = [:]

    private var speechDetectorDownload: Task<Void, Error>?

    var onModelDeleted: ((String) -> Void)?
    var onModelsChanged: (() -> Void)?

    private let logger = Logger(subsystem: AppLogger.subsystem, category: "FluidAudioModelManager")

    // Add new Fluid Audio models here when support is added.
    nonisolated private static let modelVersionMap: [String: AsrModelVersion] = [
        "parakeet-tdt-0.6b-v2": .v2,
        "parakeet-tdt-0.6b-v3": .v3,
        "parakeet-ultra": .ultra,
    ]

    private enum FluidAudioModelKind {
        case parakeet(AsrModelVersion)
        case parakeetUnified
        case nemotron(NemotronVariant)
    }

    nonisolated static func asrVersion(for modelName: String) -> AsrModelVersion {
        modelVersionMap[modelName] ?? .v3
    }

    nonisolated static func isParakeetUnifiedModel(named modelName: String) -> Bool {
        modelName == "parakeet-unified-0.6b"
    }

    nonisolated static let parakeetUnifiedPrecision: UnifiedEncoderPrecision = .int8
    nonisolated static let parakeetUnifiedStreamingConfig = UnifiedConfig(
        leftFrames: 70,
        chunkFrames: 7,
        rightFrames: 7
    )
    nonisolated static var parakeetUnifiedStreamingVariant: String? {
        parakeetUnifiedPrecision == .fp16 ? "fp16" : nil
    }
    nonisolated static var parakeetUnifiedOfflineVariant: String {
        parakeetUnifiedPrecision == .fp16 ? "offline-fp16" : "offline"
    }
    nonisolated private static let nemotronChunkMs = 1120

    nonisolated static var parakeetUnifiedStreamingEncoderFile: String {
        ModelNames.ParakeetUnified.streamingEncoderFile(
            precision: parakeetUnifiedPrecision,
            contextSuffix: parakeetUnifiedStreamingConfig.contextSuffix
        )
    }

    private enum NemotronVariant {
        case latin
        case multilingual

        init?(modelName: String) {
            switch modelName {
            case "nemotron-latin-0.6b":
                self = .latin
            case "nemotron-multilingual-0.6b":
                self = .multilingual
            default:
                return nil
            }
        }

        var downloadLanguageCode: String {
            switch self {
            case .latin:
                return "en"
            case .multilingual:
                return "auto"
            }
        }
    }

    nonisolated static func isNemotronModel(named modelName: String) -> Bool {
        NemotronVariant(modelName: modelName) != nil
    }

    nonisolated static func requiresRealtime(named modelName: String) -> Bool {
        isNemotronModel(named: modelName)
    }

    nonisolated private static func modelKind(for modelName: String) -> FluidAudioModelKind {
        if let nemotronVariant = NemotronVariant(modelName: modelName) {
            return .nemotron(nemotronVariant)
        }

        if isParakeetUnifiedModel(named: modelName) {
            return .parakeetUnified
        }

        return .parakeet(asrVersion(for: modelName))
    }

    nonisolated static func nemotronLanguageHint(from languageCode: String?) -> String {
        let trimmed = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "auto" }

        let dashed = trimmed.replacingOccurrences(of: "_", with: "-")
        return dashed.lowercased() == "auto" ? "auto" : dashed
    }

    nonisolated static func nemotronCacheDirectory(for modelName: String) -> URL {
        nemotronCacheDirectory(for: NemotronVariant(modelName: modelName) ?? .multilingual)
    }

    nonisolated private static func nemotronCacheDirectory(for variant: NemotronVariant) -> URL {
        let languageDirectory = StreamingNemotronMultilingualAsrManager.languageDirectory(
            for: variant.downloadLanguageCode
        )
        return fluidAudioModelsRootDirectory()
            .appendingPathComponent(Repo.nemotronMultilingual.folderName, isDirectory: true)
            .appendingPathComponent(languageDirectory, isDirectory: true)
            .appendingPathComponent("\(nemotronChunkMs)ms", isDirectory: true)
    }

    nonisolated static func languageHint(from languageCode: String?, for modelName: String) -> Language? {
        guard !isParakeetUnifiedModel(named: modelName),
            !isNemotronModel(named: modelName),
            asrVersion(for: modelName).isV3Family,
            let languageCode,
            languageCode != "auto"
        else { return nil }

        return Language(rawValue: languageCode)
    }

    deinit {
        for task in activeDownloadTasks.values { task.cancel() }
        speechDetectorDownload?.cancel()
    }

    // MARK: - Query helpers

    func isFluidAudioModelDownloaded(named modelName: String) -> Bool {
        switch Self.modelKind(for: modelName) {
        case .nemotron(let variant):
            return Self.nemotronRequiredFilesExist(in: Self.nemotronCacheDirectory(for: variant))
        case .parakeetUnified:
            let directory = cacheDirectory(for: modelName)
            return Self.parakeetUnifiedRequiredFiles.allSatisfy {
                Self.modelFileIsReady(at: directory.appendingPathComponent($0))
            }
        case .parakeet(let version):
            return AsrModels.modelsExist(at: cacheDirectory(for: version), version: version)

        }
    }

    func isFluidAudioModelDownloaded(_ model: FluidAudioModel) -> Bool {
        isFluidAudioModelDownloaded(named: model.name)
    }

    func isFluidAudioModelDownloading(_ model: FluidAudioModel) -> Bool {
        downloadStatuses[model.name] != nil
    }

    func downloadStatus(for model: FluidAudioModel) -> FluidAudioDownloadStatus? {
        downloadStatuses[model.name]
    }

    // MARK: - Download

    func startDownload(_ model: FluidAudioModel) {
        guard activeDownloadTasks[model.name] == nil else { return }
        activeDownloadTasks[model.name] = Task { [weak self] in
            guard let self else { return }
            await self.downloadFluidAudioModel(model)
            self.activeDownloadTasks[model.name] = nil
        }
    }

    func cancelDownload(_ model: FluidAudioModel) {
        activeDownloadTasks[model.name]?.cancel()
        if activeDownloadTasks.values.allSatisfy(\.isCancelled) { speechDetectorDownload?.cancel() }
    }

    private func downloadFluidAudioModel(_ model: FluidAudioModel) async {
        if isFluidAudioModelDownloading(model) || (isFluidAudioModelDownloaded(model) && Self.vadModelFilesExist()) {
            return
        }

        let modelName = model.name
        let downloadID = UUID()
        activeDownloadIDs[modelName] = downloadID
        activeNetworkProgressIDs[modelName] = downloadID
        downloadStatuses[modelName] = FluidAudioDownloadStatus(
            fractionCompleted: 0.0,
            message: String(localized: "Preparing FluidAudio download...")
        )
        defer {
            clearDownloadStatus(for: modelName, downloadID: downloadID)
            onModelsChanged?()
        }

        // Coalesce chunk callbacks before they reach the main actor and invalidate SwiftUI.
        let (progressStream, progressContinuation) = AsyncStream<DownloadProgress>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let progressTask = Task { @MainActor [weak self] in
            for await progress in progressStream {
                guard !Task.isCancelled else { break }
                self?.updateDownloadProgress(progress, for: modelName, downloadID: downloadID)
                do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
            }
        }
        defer {
            progressContinuation.finish()
            progressTask.cancel()
        }
        let progressHandler: ProgressHandler = { progress in
            progressContinuation.yield(progress)
        }
        do {
            if !Self.vadModelFilesExist() {
                try await downloadSpeechDetector()
                try Task.checkCancellation()
            }
            // A model installed before VAD support only needs the shared speech detector.
            guard !isFluidAudioModelDownloaded(model) else { return }
            switch Self.modelKind(for: modelName) {
            case .parakeetUnified:
                try await ModelHub.download(
                    .parakeetUnified,
                    to: Self.fluidAudioModelsRootDirectory(),
                    variant: Self.parakeetUnifiedOfflineVariant,
                    additionalModelNames: [Self.parakeetUnifiedStreamingEncoderFile],
                    progressHandler: Self.downloadOnlyProgressHandler(forwarding: progressHandler)
                )
                try Task.checkCancellation()
                beginModelPreparation(for: modelName, downloadID: downloadID)
                try await Self.optimizeParakeetUnifiedRealtimeModel()
                try Task.checkCancellation()
                try await Self.optimizeParakeetUnifiedBatchModel()
                try Task.checkCancellation()
            case .nemotron(let variant):
                let modelDirectory = try await StreamingNemotronMultilingualAsrManager.downloadVariant(
                    languageCode: variant.downloadLanguageCode,
                    chunkMs: Self.nemotronChunkMs,
                    progressHandler: progressHandler
                )
                try Task.checkCancellation()
                beginModelPreparation(for: modelName, downloadID: downloadID)
                let manager = StreamingNemotronMultilingualAsrManager()
                do {
                    try await manager.loadModels(from: modelDirectory)
                } catch {
                    await manager.cleanup()
                    throw error
                }
                await manager.cleanup()
                try Task.checkCancellation()
            case .parakeet(let version):
                guard let repo = Self.parakeetRepo(for: version) else {
                    throw AsrModelsError.loadingFailed("Unsupported Parakeet model version.")
                }
                let cacheDirectory = AsrModels.defaultCacheDirectory(for: version)
                try await ModelHub.download(
                    repo,
                    to: cacheDirectory.deletingLastPathComponent(),
                    variant: version == .v3 ? ParakeetEncoderPrecision.int8.rawValue : nil,
                    additionalModelNames: [ModelNames.ASR.vocabularyFile],
                    progressHandler: Self.downloadOnlyProgressHandler(forwarding: progressHandler)
                )
                try Task.checkCancellation()
                beginModelPreparation(for: modelName, downloadID: downloadID)
                _ = try await AsrModels.load(
                    from: cacheDirectory,
                    version: version,
                    encoderPrecision: .int8
                )
                try Task.checkCancellation()
            }
            try Task.checkCancellation()
            modelStateRevision += 1
        } catch {
            if error is CancellationError || Task.isCancelled {
                // FluidAudio validates and resumes partial downloads on the next attempt.
                modelStateRevision += 1
            } else {
                logger.error("❌ FluidAudio download failed for \(modelName, privacy: .public): \(AppLogger.errorMetadata(error), privacy: .public)")
                NotificationManager.shared.showNotification(
                    title: String(format: Localization.Models.downloadFailedForModel, model.displayName),
                    type: .error
                )
            }
        }
    }

    private func downloadSpeechDetector() async throws {
        while let current = speechDetectorDownload {
            if !current.isCancelled { return try await current.value }
            // Let the cancelled writer close its partial file before resuming it.
            _ = await current.result
            if speechDetectorDownload == current { speechDetectorDownload = nil }
            try Task.checkCancellation()
        }
        let task = Task {
            try await ModelHub.download(.vad, to: Self.fluidAudioModelsRootDirectory())
        }
        speechDetectorDownload = task
        defer { if speechDetectorDownload == task { speechDetectorDownload = nil } }
        try await task.value
    }

    nonisolated private static func optimizeParakeetUnifiedRealtimeModel() async throws {
        let streamingManager = StreamingUnifiedAsrManager(
            config: parakeetUnifiedStreamingConfig,
            encoderPrecision: parakeetUnifiedPrecision
        )
        do {
            try await streamingManager.loadModels(from: parakeetUnifiedCacheDirectory())
        } catch {
            await streamingManager.cleanup()
            throw error
        }
        await streamingManager.cleanup()
    }

    nonisolated private static func optimizeParakeetUnifiedBatchModel() async throws {
        let batchManager = UnifiedAsrManager(encoderPrecision: parakeetUnifiedPrecision)
        do {
            try await batchManager.loadModels(from: parakeetUnifiedCacheDirectory())
        } catch {
            await batchManager.cleanup()
            throw error
        }
        await batchManager.cleanup()
    }

    // MARK: - Delete

    func deleteFluidAudioModel(_ model: FluidAudioModel) {
        let cacheDirectory = cacheDirectory(for: model)

        do {
            if FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try FileManager.default.removeItem(at: cacheDirectory)
            }
        } catch {
            logger.error("Could not remove FluidAudio model: \(AppLogger.errorMetadata(error), privacy: .public)")
            return
        }

        // Notify TranscriptionModelManager to clear currentTranscriptionModel if it matches
        modelStateRevision += 1
        onModelDeleted?(model.name)
    }

    // MARK: - Finder

    func showFluidAudioModelInFinder(_ model: FluidAudioModel) {
        let cacheDirectory = cacheDirectory(for: model)

        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            NSWorkspace.shared.selectFile(cacheDirectory.path, inFileViewerRootedAtPath: "")
        }
    }

    // MARK: - Private helpers

    private func cacheDirectory(for model: FluidAudioModel) -> URL {
        cacheDirectory(for: model.name)
    }

    private func cacheDirectory(for modelName: String) -> URL {
        switch Self.modelKind(for: modelName) {
        case .nemotron(let variant):
            return Self.nemotronCacheDirectory(for: variant)
        case .parakeetUnified:
            return Self.parakeetUnifiedCacheDirectory()
        case .parakeet(let version):
            return cacheDirectory(for: version)
        }
    }

    private func cacheDirectory(for version: AsrModelVersion) -> URL {
        AsrModels.defaultCacheDirectory(for: version)
    }

    nonisolated private static func downloadOnlyProgressHandler(
        forwarding progressHandler: ProgressHandler?
    ) -> ProgressHandler {
        { progress in
            // ModelHub reports downloads in 0...0.5, so expose the network phase as 0...1.
            let downloadFraction = min(max(progress.fractionCompleted * 2.0, 0.0), 1.0)
            progressHandler?(
                DownloadProgress(
                    fractionCompleted: downloadFraction,
                    phase: progress.phase
                ))
        }
    }

    private func beginModelPreparation(
        for modelName: String,
        downloadID: UUID,
        message: String = String(localized: "Optimizing model for your device")
    ) {
        guard activeDownloadIDs[modelName] == downloadID else { return }
        activeNetworkProgressIDs[modelName] = nil
        downloadStatuses[modelName] = FluidAudioDownloadStatus(
            fractionCompleted: 1.0,
            message: message,
            isIndeterminate: true
        )
    }

    private func clearDownloadStatus(for modelName: String, downloadID: UUID) {
        guard activeDownloadIDs[modelName] == downloadID else { return }
        activeDownloadIDs[modelName] = nil
        activeNetworkProgressIDs[modelName] = nil
        downloadStatuses[modelName] = nil
    }

    private func updateDownloadProgress(_ progress: DownloadProgress, for modelName: String, downloadID: UUID) {
        guard activeDownloadIDs[modelName] == downloadID,
            activeNetworkProgressIDs[modelName] == downloadID
        else { return }

        let reportedFraction = min(max(progress.fractionCompleted, 0.0), 1.0)
        let currentFraction = downloadStatuses[modelName]?.fractionCompleted ?? 0.0
        guard reportedFraction >= currentFraction else { return }

        let status = FluidAudioDownloadStatus(
            fractionCompleted: reportedFraction,
            message: FluidAudioModelManager.statusMessage(for: progress),
            isIndeterminate: Self.isIndeterminatePhase(progress.phase)
        )
        guard status != downloadStatuses[modelName] else { return }
        downloadStatuses[modelName] = status
    }

    private static func isIndeterminatePhase(_ phase: DownloadPhase) -> Bool {
        if case .compiling(let modelName) = phase {
            return modelName.isEmpty
        }

        return false
    }

    private static func statusMessage(for progress: DownloadProgress) -> String {
        switch progress.phase {
        case .listing:
            return String(localized: "Listing files from repository...")
        case .downloading(let completedFiles, let totalFiles):
            guard totalFiles > 0 else {
                return String(localized: "Checking cached models...")
            }
            return String(
                format: String(localized: "Downloading model files: %lld/%lld"), Int64(completedFiles),
                Int64(totalFiles))
        case .compiling(let modelName):
            guard !modelName.isEmpty else {
                return String(localized: "Finalizing models...")
            }
            return String(format: String(localized: "Compiling %@"), displayName(forModelComponent: modelName))
        }
    }

    private static func displayName(forModelComponent modelName: String) -> String {
        modelName.replacingOccurrences(of: ".mlmodelc", with: "")
    }
}
