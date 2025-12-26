import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import KeyboardShortcuts
import os
import Combine

// MARK: - Recording State Machine
enum RecordingState: Equatable {
    case idle
    case recording
    case transcribing
    case enhancing
    case busy
}

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
            AppSettings.TranscriptionSettings.recorderType = recorderType
        }
    }
    
    @Published var isMiniRecorderVisible = false {
        didSet {
            if isMiniRecorderVisible {
                showRecorderPanel()
            } else {
                hideRecorderPanel()
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
        
        // Set up bindings from ModelManager to WhisperState for backward compatibility
        setupModelManagerBindings()
        
        // Configure the session manager
        if let enhancementService = enhancementService {
            PowerModeSessionManager.shared.configure(whisperState: self, enhancementService: enhancementService)
        }
        
        // Set the whisperState reference after super.init()
        self.localTranscriptionService = LocalTranscriptionService(modelsDirectory: self.modelsDirectory, whisperState: self)
        
        setupNotifications()
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
    
    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error("Error creating recordings directory: \(error.localizedDescription)")
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()
    }
}
