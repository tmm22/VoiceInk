import SwiftUI
import AVFoundation
import Combine
import UniformTypeIdentifiers
import UserNotifications
import OSLog

// MARK: - Supporting Types

enum SnippetInsertMode {
    case replace
    case append
}

enum TranscriptFormat {
    case srt
    case vtt

    var fileExtension: String {
        switch self {
        case .srt:
            return "srt"
        case .vtt:
            return "vtt"
        }
    }

    var contentType: UTType? {
        UTType(filenameExtension: fileExtension)
    }
}

struct GenerationOutput {
    let audioData: Data
    let transcript: TranscriptBundle?
    let duration: TimeInterval
}

enum TranscriptionStage: Equatable {
    case idle
    case recording
    case transcribing
    case summarising
    case cleaning
    case complete
    case error
}

// MARK: - Provider Type

enum TTSProviderType: String, CaseIterable {
    case elevenLabs = "ElevenLabs"
    case openAI = "OpenAI"
    case google = "Google"
    case tightAss = "Tight Ass Mode"
    
    var displayName: String {
        return self.rawValue
    }
    
    var icon: String {
        switch self {
        case .elevenLabs:
            return "waveform"
        case .openAI:
            return "cpu"
        case .google:
            return "cloud"
        case .tightAss:
            return "internaldrive"
        }
    }
}

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
    @Published var selectedProvider: TTSProviderType = .openAI
    @Published var selectedTranscriptionProvider: TranscriptionProviderType = .openAI {
        didSet {
            guard selectedTranscriptionProvider != oldValue else { return }
            if transcriptionServices[selectedTranscriptionProvider] == nil {
                selectedTranscriptionProvider = defaultTranscriptionProvider
                return
            }
            if hasLoadedInitialSettings {
                UserDefaults.standard.set(selectedTranscriptionProvider.rawValue, forKey: transcriptionProviderKey)
            }
        }
    }
    @Published var selectedVoice: Voice?
    @Published var isGenerating: Bool = false
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackSpeed: Double = 1.0
    @Published var volume: Double = 0.75
    @Published var errorMessage: String?
    @Published var availableVoices: [Voice] = []
    @Published var previewingVoiceID: Voice.ID?
    @Published var previewVoiceName: String?
    @Published var isPreviewing: Bool = false
    @Published var isPreviewLoading: Bool = false
    @Published var isLoopEnabled: Bool = false
    @Published var generationProgress: Double = 0
    @Published var isMinimalistMode: Bool = false
    @Published var recentGenerations: [GenerationHistoryItem] = []
    @Published var textSnippets: [TextSnippet] = []
    @Published var batchItems: [BatchGenerationItem] = []
    @Published var isBatchRunning: Bool = false
    @Published var batchProgress: Double = 0
    @Published var pronunciationRules: [PronunciationRule] = []
    @Published var managedProvisioningEnabled: Bool = ManagedProvisioningPreferences.shared.isEnabled
    @Published var managedAccountSnapshot: ManagedAccountSnapshot?
    @Published var managedProvisioningError: String?
    @Published var managedProvisioningConfiguration: ManagedProvisioningClient.Configuration? = ManagedProvisioningPreferences.shared.currentConfiguration
    @Published var articleSummary: ArticleImportSummary?
    @Published var isSummarizingArticle: Bool = false
    @Published var articleSummaryError: String?
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
    @Published var notificationsEnabled: Bool = false
    @Published var activeStyleControls: [ProviderStyleControl] = []
    @Published var styleValues: [String: Double] = [:] {
        didSet {
            cachedStyleValues[selectedProvider] = styleValues
            persistStyleValues()
        }
    }
    @Published var isImportingFromURL: Bool = false
    @Published var appearancePreference: AppearancePreference = .system {
        didSet {
            guard appearancePreference != oldValue else { return }
            saveSettings()
        }
    }
    @Published var isInspectorEnabled: Bool = false {
        didSet {
            guard isInspectorEnabled != oldValue else { return }
            saveSettings()
        }
    }
    @Published var selectedFormat: AudioSettings.AudioFormat = .mp3 {
        didSet {
            guard selectedFormat != oldValue else { return }
            ensureFormatSupportedForSelectedProvider()
            if audioData != nil && selectedFormat != currentAudioFormat {
                clearGeneratedAudio()
            }
            saveSettings()
        }
    }
    @Published var transcriptionStage: TranscriptionStage = .idle
    @Published var transcriptionProgress: Double = 0
    @Published var transcriptionSegments: [TranscriptionSegment] = []
    @Published var transcriptionSummary: TranscriptionSummaryBlock?
    @Published var transcriptionCleanupResult: TranscriptCleanupResult?
    @Published var transcriptionError: String?
    @Published var transcriptionRecord: TranscriptionRecord?
    @Published var transcriptionText: String = ""
    @Published var transcriptionLanguage: String?
    @Published var isTranscriptionRecording: Bool = false
    @Published var transcriptionRecordingDuration: TimeInterval = 0
    @Published var transcriptionRecordingLevel: Float = 0
    @Published var transcriptionCleanupInstruction: String = ""
    @Published var transcriptionCleanupLabel: String?
    @Published var isTranscriptionInProgress: Bool = false
    @Published var elevenLabsPrompt: String = "" {
        didSet {
            guard elevenLabsPrompt != oldValue else { return }
            persistElevenLabsPrompt()
        }
    }
    @Published var elevenLabsModel: ElevenLabsModel = .defaultSelection {
        didSet {
            guard elevenLabsModel != oldValue else { return }
            persistElevenLabsModel()
            if selectedProvider == .elevenLabs {
                requestElevenLabsVoices(for: elevenLabsModel)
            }
        }
    }
    @Published var elevenLabsTags: [String] = ElevenLabsVoiceTag.defaultTokens {
        didSet {
            guard elevenLabsTags != oldValue else { return }
            normalizeElevenLabsTagsIfNeeded()
            persistElevenLabsTags()
        }
    }
    
    // MARK: - Services
    let audioPlayer: AudioPlayerService
    let previewPlayer: AudioPlayerService
    let elevenLabs: ElevenLabsService
    let openAI: OpenAIService
    let googleTTS: GoogleTTSService
    let localTTS: LocalTTSService
    let summarizationService: TextSummarizationService
    let transcriptionServices: [TranscriptionProviderType: any AudioTranscribing]
    let defaultTranscriptionProvider: TranscriptionProviderType
    let transcriptInsightsService: TranscriptInsightsServicing
    let transcriptCleanupService: TranscriptCleanupServicing
    let transcriptionRecorder = TranscriptionRecorder()
    let keychainManager = KeychainManager()

    // MARK: - Internal Properties
    var cancellables = Set<AnyCancellable>()
    var hasLoadedInitialSettings = false
    var audioData: Data?
    var currentAudioFormat: AudioSettings.AudioFormat = .mp3
    var currentTranscript: TranscriptBundle?
    
    // Hard-coded provider limits aligned with published per-request maximums
    let providerCharacterLimits: [TTSProviderType: Int] = [
        .openAI: 4_096,
        .elevenLabs: 5_000,
        .google: 5_000,
        .tightAss: 20_000
    ]
    
    static let characterCountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter
    }()
    
    let maxHistoryItems = 5
    let historyMemoryLimitBytes = 2 * 1024 * 1024
    let historyDiskLimitBytes = 50 * 1024 * 1024
    let historyCacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VoiceInk/RecentGenerations", isDirectory: true)
    }()
    let snippetsKey = "textSnippets"
    let pronunciationKey = "pronunciationRules"
    let notificationsKey = "notificationsEnabled"
    let inspectorEnabledKey = "isInspectorEnabled"
    let styleValuesKey = "providerStyleValues"
    let transcriptionProviderKey = "selectedTranscriptionProvider"
    let elevenLabsPromptKey = "elevenLabs.prompt"
    let elevenLabsModelKey = "elevenLabs.model"
    let elevenLabsTagsKey = "elevenLabs.tags"
    let styleComparisonEpsilon = 0.0001
    let batchDelimiterToken = "---"
    
    var batchTask: Task<Void, Never>?
    let notificationCenter: UNUserNotificationCenter?
    let urlContentLoader: URLContentLoading
    var cachedStyleValues: [TTSProviderType: [String: Double]] = [:]
    let translationService: TextTranslationService
    var articleSummaryTask: Task<Void, Never>?
    var isUpdatingInputFromTranslation = false
    let previewDataLoader: (URL) async throws -> Data
    let previewAudioGenerator: ((Voice, TTSProviderType, AudioSettings, [String: Double]) async throws -> Data)?
    var previewTask: Task<Void, Never>?
    var isNormalizingElevenLabsTags = false
    var elevenLabsVoiceTask: Task<Void, Never>?
    let managedProvisioningClient: ManagedProvisioningClient
    var managedProvisioningTask: Task<Void, Never>?
    var transcriptionTask: Task<Void, Never>?
    var transcriptionRecordingTimer: Timer?
    var transcriptionRecordingStart: Date?
    var transcriptionRecordingURL: URL?
    var ephemeralRecordingURLs: Set<URL> = []

    // MARK: - Computed Properties
    
    var supportedFormats: [AudioSettings.AudioFormat] {
        supportedFormats(for: selectedProvider)
    }

    var currentCharacterLimit: Int {
        characterLimit(for: selectedProvider)
    }

    var shouldHighlightCharacterOverflow: Bool {
        let limit = currentCharacterLimit
        let segments = batchSegments(from: inputText)
        guard !segments.isEmpty else { return false }
        return segments.contains { $0.count > limit }
    }

    var effectiveCharacterCount: Int {
        stripBatchDelimiters(from: inputText).count
    }

    var colorSchemeOverride: ColorScheme? {
        appearancePreference.colorScheme
    }

    var hasActiveStyleControls: Bool {
        !activeStyleControls.isEmpty
    }

    var canResetStyleControls: Bool {
        guard hasActiveStyleControls else { return false }
        return activeStyleControls.contains { canResetStyleControl($0) }
    }

    var exportFormatHelpText: String? {
        switch selectedProvider {
        case .elevenLabs:
            return "ElevenLabs currently exports MP3 files only."
        case .google:
            return "Google Cloud supports MP3 or WAV output."
        case .openAI:
            return "OpenAI offers MP3, WAV, AAC, and FLAC options."
        case .tightAss:
            return "Tight Ass Mode saves audio using the system voices in WAV format."
        }
    }

    var hasBatchableSegments: Bool {
        batchSegments(from: inputText).count > 1
    }

    var pendingBatchSegmentCount: Int {
        batchSegments(from: inputText).count
    }

    var availableTranslationLanguages: [TranslationLanguage] { TranslationLanguage.supported }

    var translationTargetLanguageDisplayName: String { translationTargetLanguage.displayName }

    var translationDetectedLanguageDisplayName: String? {
        translationResult?.detectedLanguageDisplayName
    }

    var shouldShowTranslationComparison: Bool {
        translationKeepOriginal && translationResult != nil
    }

    var canTranslate: Bool {
        translationService.hasCredentials()
    }

    var canSummarizeImports: Bool {
        summarizationService.hasCredentials()
    }

    var articleSummaryPreview: String? {
        articleSummary?.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var condensedImportPreview: String? {
        articleSummary?.condensedText?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var articleSummaryReductionDescription: String? {
        guard let summary = articleSummary,
              let condensedCount = summary.condensedWordCount,
              summary.originalWordCount > 0 else {
            return articleSummary?.wordSavingsDescription
        }

        let reduction = 1 - (Double(condensedCount) / Double(summary.originalWordCount))
        guard reduction > 0 else { return articleSummary?.wordSavingsDescription }
        let percent = Int((reduction * 100).rounded())
        return percent > 0 ? "Cuts roughly \(percent)% of the article before narration." : articleSummary?.wordSavingsDescription
    }

    var canAdoptCondensedImport: Bool {
        guard let text = condensedImportPreview else { return false }
        return !text.isEmpty
    }

    var canInsertSummaryIntoEditor: Bool {
        guard let summary = articleSummaryPreview else { return false }
        return !summary.isEmpty
    }

    var canSpeakSummary: Bool {
        canInsertSummaryIntoEditor
    }

    static func defaultPreviewLoader(url: URL) async throws -> Data {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw URLError(.unsupportedURL)
        }

        let session = SecureURLSession.makeEphemeral()
        let (data, _) = try await session.data(from: url)
        return data
    }

    var costEstimate: CostEstimate {
        let profile = ProviderCostProfile.profile(for: selectedProvider)
        return profile.estimate(for: effectiveCharacterCount)
    }

    var costEstimateSummary: String { costEstimate.summary }

    var costEstimateDetail: String? { costEstimate.detail }

    var transcriptionStageDescription: String {
        switch transcriptionStage {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording microphone input"
        case .transcribing:
            return "Transcribing audio with \(selectedTranscriptionProvider.displayName)"
        case .summarising:
            return "Generating insights"
        case .cleaning:
            return "Applying cleanup instructions"
        case .complete:
            return "Transcription complete"
        case .error:
            return "Transcription failed"
        }
    }

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
        elevenLabsService: ElevenLabsService? = nil,
        openAIService: OpenAIService? = nil,
        googleService: GoogleTTSService? = nil,
        localService: LocalTTSService? = nil,
        transcriptionServices: [TranscriptionProviderType: any AudioTranscribing] = [:],
        defaultTranscriptionProvider: TranscriptionProviderType = .openAI,
        transcriptInsightsService: TranscriptInsightsServicing? = nil,
        transcriptCleanupService: TranscriptCleanupServicing? = nil,
        managedProvisioningClient: ManagedProvisioningClient = .shared
    ) {
        self.notificationCenter = notificationCenterProvider()
        self.urlContentLoader = urlContentLoader ?? URLContentService()
        self.translationService = translationService ?? OpenAITranslationService()
        self.summarizationService = summarizationService ?? OpenAISummarizationService()
        self.audioPlayer = audioPlayer ?? AudioPlayerService()
        self.previewPlayer = previewAudioPlayer ?? AudioPlayerService()
        self.previewDataLoader = previewDataLoader
        self.previewAudioGenerator = previewAudioGenerator
        self.elevenLabs = elevenLabsService ?? ElevenLabsService()
        self.openAI = openAIService ?? OpenAIService()
        self.googleTTS = googleService ?? GoogleTTSService()
        self.localTTS = localService ?? LocalTTSService()
        
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
        self.transcriptionServices = resolvedTranscriptionServices
        self.defaultTranscriptionProvider = defaultTranscriptionProvider
        self.transcriptInsightsService = transcriptInsightsService ?? TranscriptInsightsService()
        self.transcriptCleanupService = transcriptCleanupService ?? TranscriptCleanupService()
        self.managedProvisioningClient = managedProvisioningClient
        self.selectedTranscriptionProvider = defaultTranscriptionProvider

        setupHistoryCache()
        
        setupAudioPlayer()
        setupPreviewPlayer()
        loadSavedSettings()
        ensureValidTranscriptionProviderSelection()
        hasLoadedInitialSettings = true
        updateAvailableVoices()
        
        managedProvisioningTask = Task { [weak self] in
            await self?.refreshManagedAccountSnapshot(silently: true)
        }
    }

    // MARK: - Audio Player Setup
    
    func setupAudioPlayer() {
        audioPlayer.$currentTime
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentTime)

        audioPlayer.$duration
            .receive(on: DispatchQueue.main)
            .assign(to: &$duration)

        audioPlayer.$isPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPlaying)

        // Handle loop mode
        audioPlayer.didFinishPlaying = { [weak self] in
            guard let self = self else { return }
            if self.isLoopEnabled {
                Task {
                    await self.play()
                }
            }
        }
    }

    func setupPreviewPlayer() {
        previewPlayer.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                guard let self else { return }
                self.isPreviewing = playing && self.previewingVoiceID != nil
            }
            .store(in: &cancellables)

        previewPlayer.$isBuffering
            .receive(on: DispatchQueue.main)
            .sink { [weak self] buffering in
                guard let self else { return }
                if self.previewingVoiceID == nil {
                    self.isPreviewLoading = false
                } else {
                    self.isPreviewLoading = buffering
                }
            }
            .store(in: &cancellables)

        previewPlayer.$error
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.handlePreviewError(error, voiceName: nil)
            }
            .store(in: &cancellables)

        previewPlayer.didFinishPlaying = { [weak self] in
            guard let self else { return }
            self.resetPreviewState()
        }
    }

    // MARK: - Deinit
    
    deinit {
        batchTask?.cancel()
        previewTask?.cancel()
        articleSummaryTask?.cancel()
        elevenLabsVoiceTask?.cancel()
        managedProvisioningTask?.cancel()
        transcriptionTask?.cancel()
        clearHistoryCacheDirectory()
        // Note: transcriptionRecorder.cancelRecording() cannot be called from deinit
        // as it may access @MainActor isolated state. Timer invalidation is safe.
        transcriptionRecordingTimer?.invalidate()
        transcriptionRecordingTimer = nil
    }
}
