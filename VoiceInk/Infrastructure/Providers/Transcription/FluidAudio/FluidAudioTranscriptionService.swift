import FluidAudio
import Foundation
import os.log

/// Actor-isolated so launch/wake prewarm, recording-start loads and transcription can share one
/// instance without racing on the loaded managers.
actor FluidAudioTranscriptionService: TranscriptionService {
    private enum PreparationPlan: Equatable {
        case unified
        case nemotron(String)
        case parakeet(AsrModelVersion)
    }

    private var asrManager: AsrManager?
    private var unifiedAsrManager: UnifiedAsrManager?
    private var nemotronAsrManager: StreamingNemotronMultilingualAsrManager?
    private var activeVersion: AsrModelVersion?
    private var activeNemotronModelName: String?
    private var cachedModels: AsrModels?
    private var loadingTask: (version: AsrModelVersion, task: Task<AsrModels, Error>)?
    /// In-flight manager preparation, shared by concurrent callers asking for the same model.
    private var preparation: (plan: PreparationPlan, task: Task<Void, Error>)?
    /// Transcriptions currently using a loaded manager. Actor reentrancy would otherwise let a
    /// preparation for another model (or `cleanup()`) tear the manager down mid-inference.
    private var activeInferenceCount = 0
    private var inferenceIdleWaiters: [CheckedContinuation<Void, Never>] = []
    private var vadLoad: Task<VadManager, Error>?
    private let audioConverter = AudioConverter()
    private let logger = Logger(subsystem: AppLogger.subsystem, category: "FluidAudioTranscriptionService")

    private func version(for model: any TranscriptionModel) -> AsrModelVersion {
        FluidAudioModelManager.asrVersion(for: model.name)
    }

    static func languageHint(from selectedLanguage: String?, model: any TranscriptionModel) -> Language? {
        guard model.provider == .fluidAudio else {
            return nil
        }
        return FluidAudioModelManager.languageHint(from: selectedLanguage, for: model.name)
    }

    private func cleanupLoadedManagers() async {
        while activeInferenceCount > 0 {
            await withCheckedContinuation { inferenceIdleWaiters.append($0) }
        }
        // Detach synchronously, before any suspension, so no transcription can pick up a manager
        // that is being released. Release the detached managers afterwards.
        vadLoad?.cancel()
        vadLoad = nil
        let released = (unifiedAsrManager, nemotronAsrManager, asrManager)
        unifiedAsrManager = nil
        nemotronAsrManager = nil
        asrManager = nil
        activeVersion = nil
        activeNemotronModelName = nil

        await released.0?.cleanup()
        await released.1?.cleanup()
        await released.2?.cleanup()
    }

    private func ensureModelsLoaded(for version: AsrModelVersion) async throws {
        if asrManager != nil, activeVersion == version {
            return
        }

        // Clean up existing manager but preserve cachedModels for reuse
        await cleanupLoadedManagers()

        let models = try await getOrLoadModels(for: version)

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.asrManager = manager
        self.activeVersion = version
    }

    private func ensureUnifiedModelsLoaded() async throws {
        if unifiedAsrManager != nil {
            return
        }

        await cleanupLoadedManagers()

        let manager = UnifiedAsrManager(encoderPrecision: FluidAudioModelManager.parakeetUnifiedPrecision)
        try await manager.loadModels(from: FluidAudioModelManager.parakeetUnifiedCacheDirectory())
        self.unifiedAsrManager = manager
    }

    private func ensureNemotronModelsLoaded(named modelName: String) async throws {
        if nemotronAsrManager != nil, activeNemotronModelName == modelName {
            return
        }

        await cleanupLoadedManagers()

        let manager = StreamingNemotronMultilingualAsrManager()
        try await manager.loadModels(from: FluidAudioModelManager.nemotronCacheDirectory(for: modelName))
        self.nemotronAsrManager = manager
        self.activeNemotronModelName = modelName
    }

    // Returns cached models or loads from disk; deduplicates concurrent loads
    func getOrLoadModels(for version: AsrModelVersion) async throws -> AsrModels {
        if let cached = cachedModels, cached.version == version {
            return cached
        }

        // Deduplicate concurrent loads for the same version
        if let (existingVersion, existingTask) = loadingTask, existingVersion == version {
            return try await existingTask.value
        }

        let task = Task {
            let cacheDirectory = AsrModels.defaultCacheDirectory(for: version)
            guard AsrModels.modelsExist(at: cacheDirectory, version: version) else {
                throw AsrModelsError.loadingFailed(
                    "Parakeet model files are incomplete. Download the model from AI Models."
                )
            }
            return try await AsrModels.load(
                from: cacheDirectory,
                configuration: nil,
                version: version,
                encoderPrecision: .int8
            )
        }
        loadingTask = (version, task)

        defer {
            if loadingTask?.task == task { loadingTask = nil }
        }
        let models = try await task.value
        if loadingTask?.task == task { cachedModels = models }
        return models
    }

    func loadModel(for model: FluidAudioModel) async throws {
        if FluidAudioModelManager.isNemotronModel(named: model.name) {
            // Realtime Nemotron uses a dedicated streaming manager; batch loads lazily in transcribe().
            return
        }

        try await prepareModels(for: model)
    }

    /// Loads every manager `transcribe` will need for `model` without running inference.
    /// Used by both `transcribe` and the launch/wake prewarm so the two stay in lockstep.
    /// Concurrent requests for the same model share one preparation; a request for another model
    /// waits for the in-flight switch to settle, so two callers never build duplicate managers.
    func prepareModels(for model: any TranscriptionModel) async throws {
        let plan = preparationPlan(for: model)

        while let current = preparation {
            if current.plan == plan {
                return try await current.task.value
            }
            _ = await current.task.result
            if preparation?.task == current.task { preparation = nil }
        }

        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            try await self.prepare(plan)
        }
        preparation = (plan, task)
        defer {
            if preparation?.task == task { preparation = nil }
        }
        try await task.value
    }

    private func preparationPlan(for model: any TranscriptionModel) -> PreparationPlan {
        if FluidAudioModelManager.isParakeetUnifiedModel(named: model.name) { return .unified }
        if FluidAudioModelManager.isNemotronModel(named: model.name) { return .nemotron(model.name) }
        return .parakeet(version(for: model))
    }

    /// Whether the managers `plan` needs are loaded right now.
    private func isLoaded(_ plan: PreparationPlan) -> Bool {
        switch plan {
        case .unified: unifiedAsrManager != nil
        case .nemotron(let name): nemotronAsrManager != nil && activeNemotronModelName == name
        case .parakeet(let version): asrManager != nil && activeVersion == version
        }
    }

    private func prepare(_ plan: PreparationPlan) async throws {
        switch plan {
        case .unified:
            try await ensureUnifiedModelsLoaded()
        case .nemotron(let modelName):
            try await ensureNemotronModelsLoaded(named: modelName)
        case .parakeet(let version):
            try await ensureModelsLoaded(for: version)
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws
        -> String
    {
        // Another caller can switch models between our preparation finishing and this task resuming.
        // Claim the managers only once they are verifiably the ones this model needs.
        let plan = preparationPlan(for: model)
        var attempts = 0
        repeat {
            try await prepareModels(for: model)
            attempts += 1
            try Task.checkCancellation()
        } while !isLoaded(plan) && attempts < 3
        guard isLoaded(plan) else {
            logger.error("FluidAudio models were replaced repeatedly during preparation")
            throw ASRError.notInitialized
        }
        // No suspension between the check and claiming the managers.
        activeInferenceCount += 1
        defer { finishInference() }
        try Task.checkCancellation()
        guard let vad = try await speechDetector() else {
            return try await runInference(audioURL: audioURL, model: model, context: context)
        }
        let filteredURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")
        defer {
            // Best effort: the filter may have failed before creating its output.
            try? FileManager.default.removeItem(at: filteredURL)
        }
        let hasSpeech: Bool
        do {
            hasSpeech = try await FluidAudioSpeechFilter.writeSpeech(from: audioURL, to: filteredURL, using: vad)
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            logger.notice("Speech filtering failed. Using original recording: \(AppLogger.errorMetadata(error), privacy: .public)")
            return try await runInference(audioURL: audioURL, model: model, context: context)
        }
        try Task.checkCancellation()
        guard hasSpeech else { return "" }
        return try await runInference(audioURL: filteredURL, model: model, context: context)
    }

    private func finishInference() {
        activeInferenceCount -= 1
        guard activeInferenceCount == 0 else { return }
        let waiters = inferenceIdleWaiters
        inferenceIdleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func runInference(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext)
        async throws -> String
    {
        if FluidAudioModelManager.isParakeetUnifiedModel(named: model.name) {
            guard let unifiedAsrManager else {
                throw ASRError.notInitialized
            }

            let speechAudio = try loadAudioSamples(from: audioURL)
            let text = try await unifiedAsrManager.transcribe(speechAudio)
            return text
        }

        if FluidAudioModelManager.isNemotronModel(named: model.name) {
            guard let nemotronAsrManager else {
                throw ASRError.notInitialized
            }

            let compatibleLanguage = TranscriptionLanguageSupport.validLanguageOrFallback(
                context.language,
                for: model
            )
            let languageHint = FluidAudioModelManager.nemotronLanguageHint(from: compatibleLanguage)
            await nemotronAsrManager.setLanguage(languageHint)
            await nemotronAsrManager.reset()

            var speechAudio = try loadAudioSamples(from: audioURL)
            let trailingSilenceSamples = 16_000
            let maxSingleChunkSamples = 240_000
            if speechAudio.count + trailingSilenceSamples <= maxSingleChunkSamples {
                speechAudio += [Float](repeating: 0, count: trailingSilenceSamples)
            }

            _ = try await nemotronAsrManager.process(samples: speechAudio)
            let text = try await nemotronAsrManager.finish()
            return text
        }

        guard let asrManager = asrManager else {
            throw ASRError.notInitialized
        }

        let languageHint = Self.languageHint(
            from: context.language,
            model: model
        )
        var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        let result = try await asrManager.transcribe(
            audioURL,
            decoderState: &decoderState,
            language: languageHint
        )

        return result.text
    }

    private func loadAudioSamples(from audioURL: URL) throws -> [Float] {
        try audioConverter.resampleAudioFile(audioURL)
    }

    private func speechDetector() async throws -> VadManager? {
        try Task.checkCancellation()
        guard UserDefaults.standard.bool(forKey: "IsVADEnabled") else { return nil }
        if vadLoad == nil {
            guard FluidAudioModelManager.vadModelFilesExist() else { return nil }
            vadLoad = Task { try await FluidAudioSpeechFilter.loadLocalModel() }
        }
        guard let loading = vadLoad else { return nil }
        do {
            let manager = try await loading.value
            try Task.checkCancellation()
            return manager
        } catch {
            if vadLoad == loading && !Task.isCancelled { vadLoad = nil }
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            logger.notice("Speech detector unavailable: \(AppLogger.errorMetadata(error), privacy: .public)")
            return nil
        }
    }

    func detectedSpeechSegments(in samples: [Float]) async throws -> [VadSegment]? {
        guard let manager = try await speechDetector() else { return nil }
        do {
            let segments = try await manager.segmentSpeech(samples)
            try Task.checkCancellation()
            return segments
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            logger.notice("Speech segmentation failed: \(AppLogger.errorMetadata(error), privacy: .public)")
            return nil
        }
    }

    func preparedSpeechAudio(in samples: [Float]) async throws -> [Float] {
        guard let segments = try await detectedSpeechSegments(in: samples) else { return samples }
        return segments.flatMap { segment -> ArraySlice<Float> in
            let start = min(max(0, segment.startSample(sampleRate: VadManager.sampleRate)), samples.count)
            let end = min(max(start, segment.endSample(sampleRate: VadManager.sampleRate)), samples.count)
            return samples[start..<end]
        }
    }

    // Releases ASR resources but preserves cached models for reuse. Waits for an in-flight load so
    // its managers are not assigned after cleanup and left resident.
    func cleanup() async {
        if let current = preparation {
            _ = await current.task.result
        }
        await cleanupLoadedManagers()
    }

}
