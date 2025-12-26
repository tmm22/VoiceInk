import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import KeyboardShortcuts
import os
import Combine
import CoreMedia

@MainActor
class WhisperState: NSObject, ObservableObject, RecordingSessionDelegate {
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

    @Published var recorderType: String = AppSettings.TranscriptionSettings.recorderType ?? "mini" {
        didSet {
            if isMiniRecorderVisible {
                if oldValue == "notch" {
                    notchWindowManager?.hide()
                    notchWindowManager = nil
                } else {
                    miniWindowManager?.hide()
                    miniWindowManager = nil
                }
                Task { @MainActor [weak self] in
                    // Best-effort delay; ignore cancellation.
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    self?.showRecorderPanel()
                }
            }
            // Notify UIManager of recorder type change
            uiManager?.handleRecorderTypeChange(from: oldValue, to: recorderType)
            AppSettings.TranscriptionSettings.recorderType = recorderType
        }
    }
    
    @Published var isMiniRecorderVisible = false {
        didSet {
            if isMiniRecorderVisible {
                uiManager?.showRecordingUI()
            } else {
                uiManager?.hideRecordingUI()
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
    
    // MARK: - Model Manager (Phase 1 Refactoring)
    
    /// The ModelManager coordinates all model providers
    /// This is the new architecture for model management
    let modelManager: ModelManager

    /// The RecordingSessionManager handles recording lifecycle
    /// This is the new architecture for recording session management
    var recordingSessionManager: RecordingSessionManager!

    /// The TranscriptionProcessor handles transcription processing
    /// This is the new architecture for transcription processing (Phase 3)
    var transcriptionProcessor: TranscriptionProcessor!

    /// The UIManager handles UI state and interactions
    /// This is the new architecture for UI management (Phase 4)
    var uiManager: UIManager!
    
    // MARK: - Transcription Services
    
    private(set) var localTranscriptionService: LocalTranscriptionService?
    private(set) lazy var cloudTranscriptionService = CloudTranscriptionService()
    private(set) lazy var nativeAppleTranscriptionService = NativeAppleTranscriptionService()
    internal lazy var parakeetTranscriptionService = ParakeetTranscriptionService()
    internal lazy var fastConformerTranscriptionService = FastConformerTranscriptionService(modelsDirectory: fastConformerModelsDirectory)
    internal lazy var senseVoiceTranscriptionService = SenseVoiceTranscriptionService(modelsDirectory: senseVoiceModelsDirectory)
    
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
    let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "WhisperState")
    var notchWindowManager: NotchWindowManager?
    var miniWindowManager: MiniWindowManager?
    
    // For model progress tracking
    @Published var downloadProgress: [String: Double] = [:]
    @Published var parakeetDownloadStates: [String: Bool] = [:]
    @Published var fastConformerDownloadProgress: [String: Double] = [:]
    @Published var senseVoiceDownloadProgress: [String: Double] = [:]
    
    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    init(modelContext: ModelContext, enhancementService: AIEnhancementService? = nil) {
        self.modelContext = modelContext
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.tmm22.VoiceLinkCommunity")
        
        self.modelsDirectory = appSupportDirectory.appendingPathComponent("WhisperModels")
        self.fastConformerModelsDirectory = appSupportDirectory.appendingPathComponent("FastConformer")
        self.senseVoiceModelsDirectory = appSupportDirectory.appendingPathComponent("SenseVoice")
        self.recordingsDirectory = appSupportDirectory.appendingPathComponent("Recordings")
        
        self.enhancementService = enhancementService
        self.licenseViewModel = LicenseViewModel()
        
        // Initialize ModelManager with the models directory
        self.modelManager = ModelManager(modelsDirectory: self.modelsDirectory)

        super.init()

        // Initialize RecordingSessionManager after super.init()
        self.recordingSessionManager = RecordingSessionManager(
            recorder: self.recorder,
            recordingsDirectory: self.recordingsDirectory,
            delegate: self
        )

        // Initialize TranscriptionProcessor after super.init()
        self.transcriptionProcessor = TranscriptionProcessor()
        configureTranscriptionProcessor()

        // Initialize UIManager after super.init()
        self.uiManager = UIManager(whisperState: self)
        
        // Set up bindings from ModelManager to WhisperState for backward compatibility
        setupModelManagerBindings()
        
        // Configure the session manager
        if let enhancementService = enhancementService {
            PowerModeSessionManager.shared.configure(whisperState: self, enhancementService: enhancementService)
        }
        
        // Set the whisperState reference after super.init()
        self.localTranscriptionService = LocalTranscriptionService(modelsDirectory: self.modelsDirectory, whisperState: self)
        
        uiManager?.setupNotifications()
        createModelsDirectoryIfNeeded()
        createFastConformerDirectoryIfNeeded()
        createSenseVoiceDirectoryIfNeeded()
        createRecordingsDirectoryIfNeeded()
        loadAvailableModels()
        loadCurrentTranscriptionModel()
        refreshAllAvailableModels()
    }
    
    // MARK: - ModelManager Bindings
    
    /// Set up Combine bindings to sync ModelManager state with WhisperState
    /// This ensures backward compatibility while delegating to ModelManager
    private func setupModelManagerBindings() {
        // Sync local provider's whisperModels to availableModels
        modelManager.localProvider.$whisperModels
            .sink { [weak self] models in
                self?.availableModels = models
            }
            .store(in: &cancellables)
        
        // Sync local provider's isModelLoaded
        modelManager.localProvider.$isModelLoaded
            .sink { [weak self] loaded in
                self?.isModelLoaded = loaded
            }
            .store(in: &cancellables)
        
        // Sync local provider's loadedModel
        modelManager.localProvider.$loadedModel
            .sink { [weak self] model in
                self?.loadedLocalModel = model
            }
            .store(in: &cancellables)
        
        // Sync local provider's isModelLoading
        modelManager.localProvider.$isModelLoading
            .sink { [weak self] loading in
                self?.isModelLoading = loading
            }
            .store(in: &cancellables)
        
        // Sync local provider's download progress
        modelManager.localProvider.$downloadProgress
            .sink { [weak self] progress in
                guard let self = self else { return }
                // Merge local provider progress into WhisperState's downloadProgress
                for (key, value) in progress {
                    self.downloadProgress[key] = value
                }
            }
            .store(in: &cancellables)
        
        // Sync ModelManager's allAvailableModels
        modelManager.$allAvailableModels
            .sink { [weak self] models in
                self?.allAvailableModels = models
            }
            .store(in: &cancellables)
        
        // Sync ModelManager's currentModel
        modelManager.$currentModel
            .sink { [weak self] model in
                self?.currentTranscriptionModel = model
            }
            .store(in: &cancellables)
        
        // Sync Parakeet download states
        modelManager.parakeetProvider.$downloadStates
            .sink { [weak self] states in
                self?.parakeetDownloadStates = states
            }
            .store(in: &cancellables)
        
        // Sync Parakeet download progress
        modelManager.parakeetProvider.$downloadProgress
            .sink { [weak self] progress in
                guard let self = self else { return }
                // Merge Parakeet progress into WhisperState's downloadProgress
                for (key, value) in progress {
                    self.downloadProgress[key] = value
                }
            }
            .store(in: &cancellables)
    }

    /// Configure the TranscriptionProcessor with available services
    private func configureTranscriptionProcessor() {
        // Register transcription services with the processor
        if let localService = localTranscriptionService {
            transcriptionProcessor.registerService(localService, for: ModelProvider.local.rawValue)
        }
        transcriptionProcessor.registerService(parakeetTranscriptionService, for: ModelProvider.parakeet.rawValue)
        transcriptionProcessor.registerService(fastConformerTranscriptionService, for: ModelProvider.fastConformer.rawValue)
        transcriptionProcessor.registerService(senseVoiceTranscriptionService, for: ModelProvider.senseVoice.rawValue)
        transcriptionProcessor.registerService(nativeAppleTranscriptionService, for: ModelProvider.nativeApple.rawValue)
        transcriptionProcessor.registerService(cloudTranscriptionService, for: "cloud")
        // Note: Other cloud providers would be registered here as well

        // Configure enhancement and prompt detection services
        transcriptionProcessor.configure(
            enhancementService: enhancementService,
            promptDetectionService: promptDetectionService
        )
    }
    
    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error("Error creating recordings directory: \(error.localizedDescription)")
        }
    }

    // MARK: - RecordingSessionDelegate

    func sessionDidStart() {
        // Recording session started successfully
        logger.info("🎙️ Recording session started")
        recordingState = .recording
    }

    func sessionDidComplete(audioURL: URL) {
        // Recording completed, now transcribe
        Task {
            let transcription = await createTranscription(from: audioURL)
            await transcribeAudio(on: transcription)
        }
    }

    func sessionDidCancel() {
        // Recording was cancelled
        logger.info("🚫 Recording session cancelled")
        recordingState = .idle
        shouldCancelRecording = false
    }

    func sessionDidFail(error: Error) {
        // Recording failed
        logger.error("❌ Recording session failed: \(error.localizedDescription)")
        recordingState = .idle
        shouldCancelRecording = false

        // Use UIManager to show error
        uiManager?.showError(error)
    }

    private func createTranscription(from audioURL: URL) async -> Transcription {
        let audioAsset = AVURLAsset(url: audioURL)
        let duration: TimeInterval
        do {
            let assetDuration = try await audioAsset.load(.duration)
            duration = CMTimeGetSeconds(assetDuration)
        } catch {
            logger.error("Failed to load recording duration: \(error.localizedDescription)")
            duration = 0.0
        }

        let transcription = Transcription(
            text: "",
            duration: duration,
            audioFileURL: audioURL.absoluteString,
            transcriptionStatus: .pending
        )
        modelContext.insert(transcription)
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save transcription: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)

        return transcription
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()
    }
}
