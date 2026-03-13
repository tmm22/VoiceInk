import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import KeyboardShortcuts
import os

@MainActor
class WhisperState: NSObject, ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var isModelLoaded = false
    @Published var loadedLocalModel: WhisperModel?
    @Published var currentTranscriptionModel: (any TranscriptionModel)?
    @Published var isModelLoading = false
    @Published var availableModels: [WhisperModel] = []
    @Published var allAvailableModels: [any TranscriptionModel] = PredefinedModels.models
    @Published var clipboardMessage = ""
    @Published var miniRecorderError: String?
    @Published var shouldCancelRecording = false
    var partialTranscript: String = ""
    var currentSession: TranscriptionSession?


    @Published var recorderType: String = UserDefaults.standard.string(forKey: "RecorderType") ?? "mini" {
        didSet {
            if isMiniRecorderVisible {
                if oldValue == "notch" {
                    notchWindowManager?.hide()
                    notchWindowManager = nil
                } else {
                    miniWindowManager?.hide()
                    miniWindowManager = nil
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    showRecorderPanel()
                }
            }
            UserDefaults.standard.set(recorderType, forKey: "RecorderType")
        }
    }

    @Published var isMiniRecorderVisible = false {
        didSet {
            // Dispatch asynchronously to avoid "Publishing changes from within view updates" warning
            DispatchQueue.main.async { [self] in
                if isMiniRecorderVisible {
                    showRecorderPanel()
                } else {
                    hideRecorderPanel()
                }
            }
        }
    }

    var whisperContext: WhisperContext?
    let recorder = Recorder()
    var recordedFile: URL? = nil
    let whisperPrompt = WhisperPrompt()

    // Prompt detection service for trigger word handling
    let promptDetectionService = PromptDetectionService()

    let modelContext: ModelContext

    internal var serviceRegistry: TranscriptionServiceRegistry!

    private var modelUrl: URL? {
        let possibleURLs = [
            Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin", subdirectory: "Models"),
            Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin"),
            Bundle.main.bundleURL.appendingPathComponent("Models/ggml-base.en.bin")
        ]

        for url in possibleURLs {
            if let url = url, FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private enum LoadError: Error {
        case couldNotLocateModel
    }

    let modelsDirectory: URL
    let fastConformerModelsDirectory: URL
    let senseVoiceModelsDirectory: URL
    let recordingsDirectory: URL
    let enhancementService: AIEnhancementService?
    var licenseViewModel: LicenseViewModel
    let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WhisperState")
    var notchWindowManager: NotchWindowManager?
    var miniWindowManager: MiniWindowManager?

    // For model progress tracking
    @Published var downloadProgress: [String: Double] = [:]
    @Published var parakeetDownloadStates: [String: Bool] = [:]
    @Published var fastConformerDownloadProgress: [String: Double] = [:]
    @Published var senseVoiceDownloadProgress: [String: Double] = [:]

    // Transcription services
    var localTranscriptionService: LocalTranscriptionService? { serviceRegistry?.localTranscriptionService }
    var cloudTranscriptionService: CloudTranscriptionService { serviceRegistry.cloudTranscriptionService }
    var nativeAppleTranscriptionService: NativeAppleTranscriptionService { serviceRegistry.nativeAppleTranscriptionService }
    var parakeetTranscriptionService: ParakeetTranscriptionService { serviceRegistry.parakeetTranscriptionService }
    lazy var fastConformerTranscriptionService = FastConformerTranscriptionService(modelsDirectory: fastConformerModelsDirectory)
    lazy var senseVoiceTranscriptionService = SenseVoiceTranscriptionService(modelsDirectory: senseVoiceModelsDirectory)

    init(modelContext: ModelContext, enhancementService: AIEnhancementService? = nil) {
        self.modelContext = modelContext
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")

        self.modelsDirectory = appSupportDirectory.appendingPathComponent("WhisperModels")
        self.fastConformerModelsDirectory = appSupportDirectory.appendingPathComponent("FastConformerModels")
        self.senseVoiceModelsDirectory = appSupportDirectory.appendingPathComponent("SenseVoiceModels")
        self.recordingsDirectory = appSupportDirectory.appendingPathComponent("Recordings")

        self.enhancementService = enhancementService
        self.licenseViewModel = LicenseViewModel()

        super.init()

        // Configure the session manager
        if let enhancementService = enhancementService {
            PowerModeSessionManager.shared.configure(whisperState: self, enhancementService: enhancementService)
        }

        // Initialize the transcription service registry
        self.serviceRegistry = TranscriptionServiceRegistry(whisperState: self, modelsDirectory: self.modelsDirectory)

        setupNotifications()
        createModelsDirectoryIfNeeded()
        createFastConformerDirectoryIfNeeded()
        createSenseVoiceDirectoryIfNeeded()
        createRecordingsDirectoryIfNeeded()
        loadAvailableModels()
        loadCurrentTranscriptionModel()
        refreshAllAvailableModels()
    }

    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error("Error creating recordings directory: \(error.localizedDescription)")
        }
    }

    func toggleRecord(powerModeId: UUID? = nil) async {
        logger.notice("toggleRecord called – state=\(String(describing: self.recordingState))")
        if recordingState == .recording {
            partialTranscript = ""
            recordingState = .transcribing
            recorder.stopRecording()
            if let recordedFile {
                if !shouldCancelRecording {
                    let audioAsset = AVURLAsset(url: recordedFile)
                    let duration = (try? CMTimeGetSeconds(await audioAsset.load(.duration))) ?? 0.0

                    let transcription = Transcription(
                        text: "",
                        duration: duration,
                        audioFileURL: recordedFile.absoluteString,
                        transcriptionStatus: .pending
                    )
                    modelContext.insert(transcription)
                    try? modelContext.save()
                    NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)

                    await transcribeAudio(on: transcription)
                } else {
                    currentSession?.cancel()
                    currentSession = nil
                    try? FileManager.default.removeItem(at: recordedFile)
                    recordingState = .idle
                    await cleanupModelResources()
                }
            } else {
                logger.error("❌ No recorded file found after stopping recording")
                currentSession?.cancel()
                currentSession = nil
                recordingState = .idle
            }
        } else {
            logger.notice("toggleRecord: entering start-recording branch")
            guard currentTranscriptionModel != nil else {
                NotificationManager.shared.showNotification(
                    title: "No AI Model Selected",
                    type: .error
                )
                return
            }
            shouldCancelRecording = false
            partialTranscript = ""
            requestRecordPermission { [self] granted in
                if granted {
                    Task {
                        do {
                            // --- Prepare permanent file URL ---
                            let fileName = "\(UUID().uuidString).wav"
                            let permanentURL = self.recordingsDirectory.appendingPathComponent(fileName)
                            self.recordedFile = permanentURL

                            // Buffer chunks from the start; session created after Power Mode resolves
                            let pendingChunks = OSAllocatedUnfairLock(initialState: [Data]())
                            self.recorder.onAudioChunk = { data in
                                pendingChunks.withLock { $0.append(data) }
                            }

                            // Start recording immediately — no waiting for network
                            try await self.recorder.startRecording(toOutputFile: permanentURL)

                            self.recordingState = .recording
                            self.logger.notice("toggleRecord: recording started successfully, state=recording")

                            // Power Mode resolves while recording runs (~50-200ms)
                            await ActiveWindowService.shared.applyConfiguration(powerModeId: powerModeId)

                            // Create session with the resolved model (skip if user already stopped)
                            if self.recordingState == .recording, let model = self.currentTranscriptionModel {
                                let session = self.serviceRegistry.createSession(for: model, onPartialTranscript: { [weak self] partial in
                                    Task { @MainActor in
                                        self?.partialTranscript = partial
                                    }
                                })
                                self.currentSession = session
                                let realCallback = try await session.prepare(model: model)

                                if let realCallback = realCallback {
                                    // Swap callback first so new chunks go straight to the session
                                    self.recorder.onAudioChunk = realCallback
                                    // Then flush anything that was buffered before the swap
                                    let buffered = pendingChunks.withLock { chunks -> [Data] in
                                        let result = chunks
                                        chunks.removeAll()
                                        return result
                                    }
                                    for chunk in buffered { realCallback(chunk) }
                                } else {
                                    self.recorder.onAudioChunk = nil
                                    pendingChunks.withLock { $0.removeAll() }
                                }
                            }

                            // Load model and capture context in background without blocking
                            Task.detached { [weak self] in
                                guard let self = self else { return }

                                // Only load model if it's a local model and not already loaded
                                if let model = await self.currentTranscriptionModel, model.provider == .local {
                                    if let localWhisperModel = await self.availableModels.first(where: { $0.name == model.name }),
                                       await self.whisperContext == nil {
                                        do {
                                            try await self.loadModel(localWhisperModel)
                                        } catch {
                                            self.logger.error("❌ Model loading failed: \(error.localizedDescription)")
                                        }
                                    }
                                } else if let parakeetModel = await self.currentTranscriptionModel as? ParakeetModel {
                                    try? await self.serviceRegistry.parakeetTranscriptionService.loadModel(for: parakeetModel)
                                }

                                if let enhancementService = self.enhancementService {
                                    await enhancementService.captureClipboardContext()
                                    await enhancementService.captureScreenContext()
                                }
                            }

                        } catch {
                            self.logger.error("❌ Failed to start recording: \(error.localizedDescription)")
                            NotificationManager.shared.showNotification(title: "Recording failed to start", type: .error)
                            self.logger.notice("toggleRecord: calling dismissMiniRecorder from error handler")
                            await self.dismissMiniRecorder()
                            // Do not remove the file on a failed start, to preserve all recordings.
                            self.recordedFile = nil
                        }
                    }
                } else {
                    logger.error("❌ Recording permission denied.")
                }
            }
        }
    }

    private func requestRecordPermission(response: @escaping (Bool) -> Void) {
        response(true)
    }

    func toggleRecord() async {
        await toggleRecord(powerModeId: nil)
    }

    func getEnhancementService() -> AIEnhancementService? {
        enhancementService
    }

    private func transcribeAudio(on transcription: Transcription) async {
        guard let urlString = transcription.audioFileURL, let url = URL(string: urlString) else {
            logger.error("❌ Invalid audio file URL in transcription object.")
            recordingState = .idle
            transcription.text = "Transcription Failed: Invalid audio file URL"
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
            try? modelContext.save()
            return
        }

        if shouldCancelRecording {
            recordingState = .idle
            await cleanupModelResources()
            return
        }

        recordingState = .transcribing

        // Play stop sound when transcription starts with a small delay
        Task {
            let isSystemMuteEnabled = UserDefaults.standard.bool(forKey: "isSystemMuteEnabled")
            if isSystemMuteEnabled {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200 milliseconds delay
            }
            SoundManager.shared.playStopSound()
        }

        defer {
            if shouldCancelRecording {
                Task {
                    await cleanupModelResources()
                }
            }
        }

        logger.notice("🔄 Starting transcription...")

        var finalPastedText: String?
        var promptDetectionResult: PromptDetectionService.PromptDetectionResult?

        do {
            guard let model = currentTranscriptionModel else {
                throw WhisperStateError.transcriptionFailed
            }

            let transcriptionStart = Date()
            var text: String
            if let session = currentSession {
                text = try await session.transcribe(audioURL: url)
                currentSession = nil
            } else {
                text = try await serviceRegistry.transcribe(audioURL: url, model: model)
            }
            logger.debug("Transcript received. Character count: \(text.count, privacy: .public)")
            text = TranscriptionOutputFilter.filter(text)
            logger.debug("Transcript output filter applied. Character count: \(text.count, privacy: .public)")
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)

            let powerModeManager = PowerModeManager.shared
            let activePowerModeConfig = powerModeManager.currentActiveConfiguration
            let powerModeName = (activePowerModeConfig?.isEnabled == true) ? activePowerModeConfig?.name : nil
            let powerModeEmoji = (activePowerModeConfig?.isEnabled == true) ? activePowerModeConfig?.emoji : nil

            if await checkCancellationAndCleanup() { return }

            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if UserDefaults.standard.bool(forKey: "IsTextFormattingEnabled") {
                text = WhisperTextFormatter.format(text)
                logger.debug("Transcript formatting applied. Character count: \(text.count, privacy: .public)")
            }

            text = WordReplacementService.shared.applyReplacements(to: text)
            logger.debug("Word replacements applied. Character count: \(text.count, privacy: .public)")

            let audioAsset = AVURLAsset(url: url)
            let actualDuration = (try? CMTimeGetSeconds(await audioAsset.load(.duration))) ?? 0.0

            transcription.text = text
            transcription.duration = actualDuration
            transcription.transcriptionModelName = model.displayName
            transcription.transcriptionDuration = transcriptionDuration
            transcription.powerModeName = powerModeName
            transcription.powerModeEmoji = powerModeEmoji
            finalPastedText = text

            if let enhancementService = enhancementService, enhancementService.isConfigured {
                let detectionResult = promptDetectionService.analyzeText(text, with: enhancementService)
                promptDetectionResult = detectionResult
                await promptDetectionService.applyDetectionResult(detectionResult, to: enhancementService)
            }

            if let enhancementService = enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured {
                if await checkCancellationAndCleanup() { return }

                self.recordingState = .enhancing
                let textForAI = promptDetectionResult?.processedText ?? text

                do {
                    let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(textForAI)
                    logger.debug("AI enhancement completed. Character count: \(enhancedText.count, privacy: .public)")
                    transcription.enhancedText = enhancedText
                    transcription.aiEnhancementModelName = enhancementService.getAIService()?.currentModel
                    transcription.promptName = promptName
                    transcription.enhancementDuration = enhancementDuration
                    transcription.aiRequestSystemMessage = enhancementService.lastSystemMessageSent
                    transcription.aiRequestUserMessage = enhancementService.lastUserMessageSent
                    finalPastedText = enhancedText
                } catch {
                    transcription.enhancedText = "Enhancement failed: \(error)"

                    if await checkCancellationAndCleanup() { return }
                }
            }

            transcription.transcriptionStatus = TranscriptionStatus.completed.rawValue

        } catch {
            let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let recoverySuggestion = (error as? LocalizedError)?.recoverySuggestion ?? ""
            let fullErrorText = recoverySuggestion.isEmpty ? errorDescription : "\(errorDescription) \(recoverySuggestion)"

            transcription.text = "Transcription Failed: \(fullErrorText)"
            transcription.transcriptionStatus = TranscriptionStatus.failed.rawValue
        }

        try? modelContext.save()

        if transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
            NotificationCenter.default.post(name: .transcriptionCompleted, object: transcription)
        }

        if await checkCancellationAndCleanup() { return }

        if let textToPaste = finalPastedText, transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                CursorPaster.pasteAtCursor(textToPaste + " ")

                let powerMode = PowerModeManager.shared
                if let activeConfig = powerMode.currentActiveConfiguration, activeConfig.isAutoSendEnabled {
                    // Slight delay to ensure the paste operation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        CursorPaster.pressEnter()
                    }
                }
            }
        }

        if let result = promptDetectionResult,
           let enhancementService = enhancementService,
           result.shouldEnableAI {
            await promptDetectionService.restoreOriginalSettings(result, to: enhancementService)
        }

        await self.dismissMiniRecorder()

        shouldCancelRecording = false
    }

    private func checkCancellationAndCleanup() async -> Bool {
        if shouldCancelRecording {
            await cleanupModelResources()
            return true
        }
        return false
    }
}
