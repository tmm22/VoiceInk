import SwiftUI
import UserNotifications

@MainActor
final class TTSSettingsViewModel: ObservableObject {
    @Published var selectedProvider: TTSProviderType = .openAI {
        didSet {
            guard selectedProvider != oldValue else { return }
            guard !isLoadingSettings else { return }
            updateAvailableVoices()
            saveSettings()
        }
    }
    @Published var selectedVoice: Voice?
    @Published var availableVoices: [Voice] = []
    @Published var isMinimalistMode: Bool = false {
        didSet {
            guard isMinimalistMode != oldValue else { return }
            guard !isLoadingSettings else { return }
            saveSettings()
        }
    }
    @Published var textSnippets: [TextSnippet] = []
    @Published var pronunciationRules: [PronunciationRule] = []
    @Published var notificationsEnabled: Bool = false
    @Published var activeStyleControls: [ProviderStyleControl] = []
    @Published var styleValues: [String: Double] = [:] {
        didSet {
            cachedStyleValues[selectedProvider] = styleValues
            guard !isLoadingSettings else { return }
            persistStyleValues()
        }
    }
    @Published var appearancePreference: AppearancePreference = .system {
        didSet {
            guard appearancePreference != oldValue else { return }
            guard !isLoadingSettings else { return }
            saveSettings()
        }
    }
    @Published var isInspectorEnabled: Bool = false {
        didSet {
            guard isInspectorEnabled != oldValue else { return }
            guard !isLoadingSettings else { return }
            saveSettings()
        }
    }
    @Published var selectedFormat: AudioSettings.AudioFormat = .mp3 {
        didSet {
            guard selectedFormat != oldValue else { return }
            guard !isLoadingSettings else { return }
            let formats = supportedFormats(for: selectedProvider)
            guard formats.contains(selectedFormat) else {
                selectedFormat = formats.first ?? .mp3
                return
            }
            onSelectedFormatChanged?(selectedFormat, oldValue)
            saveSettings()
        }
    }
    @Published var elevenLabsPrompt: String = "" {
        didSet {
            guard elevenLabsPrompt != oldValue else { return }
            guard !isLoadingSettings else { return }
            persistElevenLabsPrompt()
        }
    }
    @Published var elevenLabsModel: ElevenLabsModel = .defaultSelection {
        didSet {
            guard elevenLabsModel != oldValue else { return }
            guard !isLoadingSettings else { return }
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
            guard !isLoadingSettings else { return }
            persistElevenLabsTags()
        }
    }
    @Published var managedProvisioningEnabled: Bool = ManagedProvisioningPreferences.shared.isEnabled
    @Published var managedAccountSnapshot: ManagedAccountSnapshot?
    @Published var managedProvisioningError: String?
    @Published var managedProvisioningConfiguration: ManagedProvisioningClient.Configuration? = ManagedProvisioningPreferences.shared.currentConfiguration

    let playback: TTSPlaybackViewModel
    let preview: TTSVoicePreviewViewModel
    let elevenLabs: ElevenLabsTTSService
    let openAI: OpenAITTSService
    let googleTTS: GoogleTTSService
    let localTTS: LocalTTSService
    let keychainManager: KeychainManager
    let notificationCenter: UNUserNotificationCenter?
    let managedProvisioningClient: ManagedProvisioningClient

    var onErrorMessage: ((String) -> Void)?
    var onSelectedFormatChanged: ((AudioSettings.AudioFormat, AudioSettings.AudioFormat) -> Void)?

    var cachedStyleValues: [TTSProviderType: [String: Double]] = [:]
    let providerCharacterLimits: [TTSProviderType: Int] = [
        .openAI: 4_096,
        .elevenLabs: 5_000,
        .google: 5_000,
        .tightAss: 20_000
    ]
    let styleComparisonEpsilon = 0.0001
    var isLoadingSettings = false
    var isNormalizingElevenLabsTags = false
    var elevenLabsVoiceTask: Task<Void, Never>?
    var managedProvisioningTask: Task<Void, Never>?

    static let characterCountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    init(
        playback: TTSPlaybackViewModel,
        preview: TTSVoicePreviewViewModel,
        elevenLabs: ElevenLabsTTSService,
        openAI: OpenAITTSService,
        googleTTS: GoogleTTSService,
        localTTS: LocalTTSService,
        keychainManager: KeychainManager,
        notificationCenter: UNUserNotificationCenter?,
        managedProvisioningClient: ManagedProvisioningClient
    ) {
        self.playback = playback
        self.preview = preview
        self.elevenLabs = elevenLabs
        self.openAI = openAI
        self.googleTTS = googleTTS
        self.localTTS = localTTS
        self.keychainManager = keychainManager
        self.notificationCenter = notificationCenter
        self.managedProvisioningClient = managedProvisioningClient
    }

    deinit {
        elevenLabsVoiceTask?.cancel()
        managedProvisioningTask?.cancel()
    }
}
