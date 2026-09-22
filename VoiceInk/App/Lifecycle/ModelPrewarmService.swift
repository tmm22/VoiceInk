import Combine
import Foundation
import os

@MainActor
final class ModelPrewarmService: ObservableObject {
    private let transcriptionModelManager: TranscriptionModelManager
    /// The engine's registry, so a prewarmed runtime is the one transcription actually uses.
    /// A private registry would load a second, never-used copy of FluidAudio's models.
    private let serviceRegistry: TranscriptionServiceRegistry
    /// Prewarm shares the engine's runtime, so it must not start a load while a session is active.
    private let isEngineIdle: () -> Bool
    private let logger = Logger(subsystem: AppLogger.subsystem, category: "ModelPrewarm")
    private let prewarmEnabledKey = "PrewarmModelOnWake"
    private var lifecycleCancellable: AnyCancellable?
    private var prewarmTask: Task<Void, Never>?
    private var isPrewarming = false

    init(
        transcriptionModelManager: TranscriptionModelManager, serviceRegistry: TranscriptionServiceRegistry,
        isEngineIdle: @escaping () -> Bool
    ) {
        self.transcriptionModelManager = transcriptionModelManager
        self.serviceRegistry = serviceRegistry
        self.isEngineIdle = isEngineIdle
        guard !AppRuntimeEnvironment.isRunningTests else { return }
        lifecycleCancellable = LifecycleObserver.shared.publisher(for: [.systemDidWake, .systemWillSleep]).sink {
            [weak self] event in
            Task { @MainActor [weak self] in
                if event == .systemWillSleep {
                    self?.prewarmTask?.cancel()
                } else {
                    self?.schedulePrewarm()
                }
            }
        }
        schedulePrewarmOnAppLaunch()
    }

    deinit {
        prewarmTask?.cancel()
    }

    // MARK: - Trigger Handlers

    private func schedulePrewarmOnAppLaunch() {
        schedulePrewarm()
    }

    /// Coalesce wake events. Never overlap an already-running preparation with another one.
    private func schedulePrewarm() {
        guard !isPrewarming else { return }
        prewarmTask?.cancel()
        prewarmTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return // Sleep or teardown cancelled the pending warmup.
            }
            guard !Task.isCancelled else { return }
            await self?.performPrewarm()
        }
    }

    // MARK: - Core Prewarming Logic

    /// Loads the selected local model into memory without running any inference.
    ///
    /// For Whisper this creates the whisper.cpp context, which already reads the weights,
    /// initialises the Metal backend, compiles kernels and allocates the compute graphs; a
    /// throwaway transcription would add nothing but CPU/GPU time and a spurious log entry.
    /// FluidAudio likewise loads its CoreML models at manager-load time.
    private func performPrewarm() async {
        guard !Task.isCancelled, shouldPrewarm() else { return }
        guard isEngineIdle() else {
            logger.notice("Skipping prewarm while a recording session is active")
            return
        }
        isPrewarming = true
        defer {
            isPrewarming = false
            prewarmTask = nil
        }

        guard
            let transcriptionConfiguration = ModeRuntimeResolver.transcriptionConfiguration(
                transcriptionModelManager: transcriptionModelManager
            )
        else {
            logger.notice("No model selected, skipping prewarm")
            return
        }
        let currentModel = transcriptionConfiguration.model

        logger.notice("Prewarming \(currentModel.displayName, privacy: .public)")
        let startTime = Date()

        do {
            try await serviceRegistry.prewarm(model: currentModel)
            let duration = Date().timeIntervalSince(startTime)

            logger.notice("Prewarm completed in \(String(format: "%.2f", duration), privacy: .public)s")

        } catch is CancellationError {
            logger.debug("Prewarm cancelled")
        } catch {
            logger.error("❌ Prewarm failed: \(AppLogger.errorMetadata(error), privacy: .public)")
        }
    }

    // MARK: - Validation

    private func shouldPrewarm() -> Bool {
        // Check if user has enabled prewarming
        let isEnabled = UserDefaults.standard.bool(forKey: prewarmEnabledKey)
        guard isEnabled else {
            logger.notice("Prewarm disabled by user")
            return false
        }

        // Prewarm only local runtimes that benefit from retained preparation.
        guard
            let model = ModeRuntimeResolver.transcriptionConfiguration(
                transcriptionModelManager: transcriptionModelManager
            )?.model
        else {
            return false
        }

        switch model.provider {
        case .whisper, .fluidAudio:
            return true
        default:
            logger.notice("Skipping prewarm - cloud models don't need it")
            return false
        }
    }

}
