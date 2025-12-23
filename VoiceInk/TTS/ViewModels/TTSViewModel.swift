import SwiftUI
import Combine
import UserNotifications

// MARK: - TTSViewModel

@MainActor
class TTSViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var inputText: String = "" {
        didSet {
            guard !isUpdatingInputFromTranslation else { return }
            if inputText.isEmpty {
                translationResult = nil
            } else if let existing = translationResult, existing.originalText != inputText {
                translationResult = nil
            }
        }
    }
    @Published var errorMessage: String?
    @Published var translationTargetLanguage: TranslationLanguage = .english {
        didSet {
            if translationTargetLanguage != oldValue {
                translationResult = nil
            }
        }
    }
    @Published var translationKeepOriginal: Bool = true {
        didSet {
            if translationKeepOriginal == false {
                translationResult = nil
            }
        }
    }
    @Published var translationResult: TranslationResult?
    @Published var isTranslating: Bool = false
    
    // MARK: - Services
    let playback: TTSPlaybackViewModel
    let history: TTSHistoryViewModel
    let generation: TTSSpeechGenerationViewModel
    let preview: TTSVoicePreviewViewModel
    let settings: TTSSettingsViewModel
    let importExport: TTSImportExportViewModel
    let elevenLabs: ElevenLabsTTSService
    let openAI: OpenAITTSService
    let googleTTS: GoogleTTSService
    let localTTS: LocalTTSService
    let transcription: TTSTranscriptionViewModel

    // MARK: - Internal Properties
    var cancellables = Set<AnyCancellable>()
    var audioData: Data?
    var currentAudioFormat: AudioSettings.AudioFormat = .mp3
    var currentTranscript: TranscriptBundle?

    static let batchDelimiterToken = "---"

    let translationService: TextTranslationService
    var isUpdatingInputFromTranslation = false

    // MARK: - Initialization
    
    init(
        notificationCenterProvider: @escaping () -> UNUserNotificationCenter? = { UNUserNotificationCenter.current() },
        urlContentLoader: URLContentLoading? = nil,
        translationService: TextTranslationService? = nil,
        summarizationService: TextSummarizationService? = nil,
        audioPlayer: AudioPlayerService? = nil,
        previewAudioPlayer: AudioPlayerService? = nil,
        previewDataLoader: @escaping (URL) async throws -> Data = TTSViewModel.defaultPreviewLoader,
        previewAudioGenerator: ((Voice, TTSProviderType, AudioSettings, [String: Double]) async throws -> Data)? = nil,
        elevenLabsService: ElevenLabsTTSService? = nil,
        openAIService: OpenAITTSService? = nil,
        googleService: GoogleTTSService? = nil,
        localService: LocalTTSService? = nil,
        transcriptionServices: [TranscriptionProviderType: any AudioTranscribing] = [:],
        defaultTranscriptionProvider: TranscriptionProviderType = .openAI,
        transcriptInsightsService: TranscriptInsightsServicing? = nil,
        transcriptCleanupService: TranscriptCleanupServicing? = nil,
        managedProvisioningClient: ManagedProvisioningClient? = nil
    ) {
        let resolvedNotificationCenter = notificationCenterProvider()
        let resolvedUrlContentLoader = urlContentLoader ?? URLContentService()
        self.translationService = translationService ?? OpenAITranslationService()
        let resolvedSummarizationService = summarizationService ?? OpenAISummarizationService()
        let resolvedAudioPlayer = audioPlayer ?? AudioPlayerService()
        let playbackViewModel = TTSPlaybackViewModel(audioPlayer: resolvedAudioPlayer)
        let historyViewModel = TTSHistoryViewModel(playback: playbackViewModel)
        let generationViewModel = TTSSpeechGenerationViewModel(
            playback: playbackViewModel,
            history: historyViewModel
        )
        let resolvedPreviewPlayer = previewAudioPlayer ?? AudioPlayerService()
        let previewViewModel = TTSVoicePreviewViewModel(
            playback: playbackViewModel,
            generation: generationViewModel,
            previewPlayer: resolvedPreviewPlayer,
            previewDataLoader: previewDataLoader,
            previewAudioGenerator: previewAudioGenerator
        )
        self.playback = playbackViewModel
        self.preview = previewViewModel
        let resolvedElevenLabs = elevenLabsService ?? ElevenLabsTTSService()
        let resolvedOpenAI = openAIService ?? OpenAITTSService()
        let resolvedGoogle = googleService ?? GoogleTTSService()
        let resolvedLocal = localService ?? LocalTTSService()
        self.elevenLabs = resolvedElevenLabs
        self.openAI = resolvedOpenAI
        self.googleTTS = resolvedGoogle
        self.localTTS = resolvedLocal
        self.history = historyViewModel
        self.generation = generationViewModel

        let resolvedManagedProvisioningClient = managedProvisioningClient ?? .shared
        let keychainManager = KeychainManager()
        let settingsViewModel = TTSSettingsViewModel(
            playback: playbackViewModel,
            preview: previewViewModel,
            elevenLabs: resolvedElevenLabs,
            openAI: resolvedOpenAI,
            googleTTS: resolvedGoogle,
            localTTS: resolvedLocal,
            keychainManager: keychainManager,
            notificationCenter: resolvedNotificationCenter,
            managedProvisioningClient: resolvedManagedProvisioningClient
        )
        self.settings = settingsViewModel
        let importExportViewModel = TTSImportExportViewModel(
            settings: settingsViewModel,
            playback: playbackViewModel,
            history: historyViewModel,
            generation: generationViewModel,
            urlContentLoader: resolvedUrlContentLoader,
            summarizationService: resolvedSummarizationService,
            batchDelimiterToken: Self.batchDelimiterToken
        )
        self.importExport = importExportViewModel
        
        var resolvedTranscriptionServices = transcriptionServices
        if resolvedTranscriptionServices.isEmpty {
            resolvedTranscriptionServices = [
                .openAI: OpenAITranscriptionService(),
                .googleChirp2: GoogleTranscriptionService()
            ]
        } else {
            if resolvedTranscriptionServices[.openAI] == nil {
                resolvedTranscriptionServices[.openAI] = OpenAITranscriptionService()
            }
            if resolvedTranscriptionServices[.googleChirp2] == nil {
                resolvedTranscriptionServices[.googleChirp2] = GoogleTranscriptionService()
            }
        }
        let resolvedInsightsService = transcriptInsightsService ?? TranscriptInsightsService()
        let resolvedCleanupService = transcriptCleanupService ?? TranscriptCleanupService()
        var insertTextHandler: ((String) -> Void)?
        self.transcription = TTSTranscriptionViewModel(
            transcriptionServices: resolvedTranscriptionServices,
            defaultProvider: defaultTranscriptionProvider,
            transcriptInsightsService: resolvedInsightsService,
            transcriptCleanupService: resolvedCleanupService,
            onInsertText: { text in
                insertTextHandler?(text)
            }
        )
        insertTextHandler = { [weak self] text in
            self?.inputText = text
        }

        history.coordinator = self
        generation.coordinator = self
        preview.coordinator = self
        importExport.coordinator = self
        history.setupHistoryCache()

        settings.onErrorMessage = { [weak self] message in
            self?.errorMessage = message
        }
        settings.onSelectedFormatChanged = { [weak self] newFormat, _ in
            guard let self else { return }
            if self.audioData != nil && newFormat != self.currentAudioFormat {
                self.clearGeneratedAudio()
            }
        }

        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        importExport.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        playback.onPersistSettings = { [weak settings] in
            settings?.saveSettings()
        }
        settings.loadSavedSettings()
        settings.updateAvailableVoices()
        settings.scheduleManagedProvisioningRefresh(silently: true)
    }

    // MARK: - Deinit
    
    deinit {
        cancellables.removeAll()
    }
}

extension TTSViewModel: TTSHistoryCoordinating {}
extension TTSViewModel: TTSSpeechGenerationCoordinating {}
extension TTSViewModel: TTSVoicePreviewCoordinating {}
extension TTSViewModel: TTSImportExportCoordinating {}
