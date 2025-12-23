import Foundation
import Combine

@MainActor
protocol TTSVoicePreviewCoordinating: AnyObject {
    var errorMessage: String? { get set }
    var elevenLabsModel: ElevenLabsModel { get }

    func getProvider(for type: TTSProviderType) -> any TTSProvider
    func styleValues(for provider: TTSProviderType) -> [String: Double]
}

@MainActor
final class TTSVoicePreviewViewModel: ObservableObject {
    @Published var previewingVoiceID: Voice.ID?
    @Published var previewVoiceName: String?
    @Published var isPreviewing = false
    @Published var isPreviewLoading = false

    weak var coordinator: (any TTSVoicePreviewCoordinating)?

    private let playback: TTSPlaybackViewModel
    private let generation: TTSSpeechGenerationViewModel
    private let previewPlayer: AudioPlayerService
    private let previewDataLoader: (URL) async throws -> Data
    private let previewAudioGenerator: ((Voice, TTSProviderType, AudioSettings, [String: Double]) async throws -> Data)?
    private var previewTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        playback: TTSPlaybackViewModel,
        generation: TTSSpeechGenerationViewModel,
        previewPlayer: AudioPlayerService,
        previewDataLoader: @escaping (URL) async throws -> Data,
        previewAudioGenerator: ((Voice, TTSProviderType, AudioSettings, [String: Double]) async throws -> Data)?
    ) {
        self.playback = playback
        self.generation = generation
        self.previewPlayer = previewPlayer
        self.previewDataLoader = previewDataLoader
        self.previewAudioGenerator = previewAudioGenerator
        setupBindings()
    }

    deinit {
        previewTask?.cancel()
    }

    func previewVoice(_ voice: Voice) {
        if previewingVoiceID == voice.id && (isPreviewing || isPreviewLoading) {
            stopPreview()
            return
        }

        guard coordinator != nil else { return }

        stopPreview()

        guard let providerType = TTSProviderType(rawValue: voice.provider.rawValue) else {
            coordinator?.errorMessage = "Preview not available for \(voice.name)."
            return
        }

        playback.pause()
        previewingVoiceID = voice.id
        previewVoiceName = voice.name
        isPreviewLoading = true

        previewTask = Task { [weak self] in
            guard let self else { return }

            do {
                let data = try await self.loadPreviewAudio(for: voice, providerType: providerType)
                try Task.checkCancellation()
                try await self.previewPlayer.loadAudio(from: data)
                try Task.checkCancellation()
                self.previewPlayer.setVolume(Float(self.playback.volume))
                self.previewPlayer.play()
                self.isPreviewLoading = false
                self.isPreviewing = true
            } catch is CancellationError {
                self.resetPreviewState()
            } catch {
                self.handlePreviewError(error, voiceName: voice.name)
            }

            self.previewTask = nil
        }
    }

    func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        previewPlayer.stop()
        resetPreviewState()
    }

    func isPreviewingVoice(_ voice: Voice) -> Bool {
        previewingVoiceID == voice.id && isPreviewing
    }

    func isPreviewLoadingVoice(_ voice: Voice) -> Bool {
        previewingVoiceID == voice.id && isPreviewLoading
    }

    func canPreview(_ voice: Voice) -> Bool {
        if voice.previewURL != nil {
            return true
        }

        guard let providerType = TTSProviderType(rawValue: voice.provider.rawValue) else {
            return false
        }

        if providerType == .tightAss {
            return true
        }

        guard let coordinator else { return false }
        let provider = coordinator.getProvider(for: providerType)
        return provider.hasValidAPIKey()
    }

    var isPreviewActive: Bool {
        previewingVoiceID != nil
    }

    var isPreviewPlaying: Bool {
        previewingVoiceID != nil && isPreviewing
    }

    var isPreviewLoadingActive: Bool {
        previewingVoiceID != nil && isPreviewLoading
    }
}

// MARK: - Private Helpers
private extension TTSVoicePreviewViewModel {
    func setupBindings() {
        previewPlayer.$isPlaying
            .sink { [weak self] playing in
                guard let self else { return }
                self.isPreviewing = playing && self.previewingVoiceID != nil
            }
            .store(in: &cancellables)

        previewPlayer.$isBuffering
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
            .sink { [weak self] error in
                self?.handlePreviewError(error, voiceName: nil)
            }
            .store(in: &cancellables)

        previewPlayer.didFinishPlaying = { [weak self] in
            self?.resetPreviewState()
        }
    }

    func loadPreviewAudio(for voice: Voice, providerType: TTSProviderType) async throws -> Data {
        if let previewURLString = voice.previewURL,
           let url = URL(string: previewURLString) {
            return try await previewDataLoader(url)
        }

        guard let coordinator else {
            throw TTSError.apiError("Preview coordinator unavailable.")
        }

        var settings = previewAudioSettings(for: providerType)
        let resolvedStyleValues = coordinator.styleValues(for: providerType)
        settings.styleValues = resolvedStyleValues

        if let generator = previewAudioGenerator {
            return try await generator(voice, providerType, settings, resolvedStyleValues)
        }

        let provider = coordinator.getProvider(for: providerType)

        if providerType != .tightAss && !provider.hasValidAPIKey() {
            throw VoicePreviewError.missingAPIKey(providerName: providerType.displayName)
        }

        return try await generation.synthesizeSpeechWithFallback(
            text: previewSampleText(for: voice, providerType: providerType),
            voice: voice,
            provider: provider,
            providerType: providerType,
            settings: settings
        )
    }

    func resetPreviewState() {
        previewTask = nil
        previewingVoiceID = nil
        previewVoiceName = nil
        isPreviewLoading = false
        isPreviewing = false
    }

    func handlePreviewError(_ error: Error, voiceName: String?) {
        let resolvedName = voiceName ?? previewVoiceName ?? "this voice"
        coordinator?.errorMessage = "Unable to preview \(resolvedName): \(error.localizedDescription)"
        resetPreviewState()
    }

    func previewAudioSettings(for providerType: TTSProviderType) -> AudioSettings {
        var settings = AudioSettings()
        settings.speed = min(max(playback.playbackSpeed, 0.5), 2.0)
        settings.pitch = 1.0
        settings.volume = min(max(playback.volume, 0.0), 1.0)
        settings.sampleRate = providerType == .google ? 24_000 : 22_050
        settings.format = providerType == .tightAss ? .wav : .mp3
        if providerType == .elevenLabs {
            let model = coordinator?.elevenLabsModel ?? .defaultSelection
            settings.providerOptions[ElevenLabsProviderOptionKey.modelID] = model.rawValue
        }
        return settings
    }

    func previewSampleText(for voice: Voice, providerType: TTSProviderType) -> String {
        "Hello, this is \(voice.name) with \(providerType.displayName). Here's a quick preview."
    }
}

// MARK: - Voice Preview Error
private enum VoicePreviewError: LocalizedError {
    case missingAPIKey(providerName: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let providerName):
            return "\(providerName) API key is required to preview this voice."
        }
    }
}
