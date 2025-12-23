import Foundation
import UserNotifications

@MainActor
protocol TTSSpeechGenerationCoordinating: AnyObject {
    var inputText: String { get }
    var selectedProvider: TTSProviderType { get }
    var selectedVoice: Voice? { get }
    var selectedFormat: AudioSettings.AudioFormat { get set }
    var errorMessage: String? { get set }
    var currentTranscript: TranscriptBundle? { get set }
    var audioData: Data? { get set }
    var currentAudioFormat: AudioSettings.AudioFormat { get set }
    var elevenLabsModel: ElevenLabsModel { get set }
    var notificationsEnabled: Bool { get }
    var notificationCenter: UNUserNotificationCenter? { get }

    func stopPreview()
    func getProvider(for type: TTSProviderType) -> any TTSProvider
    func currentFormatForGeneration() -> AudioSettings.AudioFormat
    func characterLimit(for provider: TTSProviderType) -> Int
    func sampleRate(for format: AudioSettings.AudioFormat) -> Int
    func styleValues(for provider: TTSProviderType) -> [String: Double]
    func applyPronunciationRules(to text: String, provider: TTSProviderType) -> String
    func stripBatchDelimiters(from text: String) -> String
    func batchSegments(from text: String) -> [String]
}

@MainActor
final class TTSSpeechGenerationViewModel: ObservableObject {
    @Published var isGenerating: Bool = false
    @Published var generationProgress: Double = 0
    @Published var batchItems: [BatchGenerationItem] = []
    @Published var isBatchRunning: Bool = false
    @Published var batchProgress: Double = 0

    weak var coordinator: (any TTSSpeechGenerationCoordinating)?

    let playback: TTSPlaybackViewModel
    let history: TTSHistoryViewModel

    var batchTask: Task<Void, Never>?

    init(playback: TTSPlaybackViewModel, history: TTSHistoryViewModel) {
        self.playback = playback
        self.history = history
    }

    deinit {
        batchTask?.cancel()
    }

    // MARK: - Speech Generation
    /// Generates speech for the current input, with long-form fallback when text exceeds limits.
    func generateSpeech() async {
        guard let coordinator else { return }

        let trimmed = coordinator.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = coordinator.stripBatchDelimiters(from: trimmed)

        guard !sanitized.isEmpty else {
            coordinator.errorMessage = "Please enter some text"
            return
        }

        coordinator.stopPreview()

        let providerType = coordinator.selectedProvider
        let provider = coordinator.getProvider(for: providerType)
        let voice = coordinator.selectedVoice ?? provider.defaultVoice
        let format = coordinator.currentFormatForGeneration()
        let providerLimit = coordinator.characterLimit(for: providerType)

        if sanitized.count > providerLimit {
            await generateLongFormSpeech(
                text: sanitized,
                providerType: providerType,
                voice: voice,
                format: format,
                shouldAutoplay: true
            )
            return
        }

        isGenerating = true
        coordinator.errorMessage = nil
        generationProgress = 0

        do {
            let preparedText = coordinator.applyPronunciationRules(to: sanitized, provider: providerType)
            let output = try await performGeneration(
                text: preparedText,
                providerType: providerType,
                voice: voice,
                format: format,
                shouldAutoplay: true
            )
            coordinator.currentTranscript = output.transcript
            history.recordGenerationHistory(
                audioData: output.audioData,
                format: format,
                text: preparedText,
                voice: voice,
                provider: providerType,
                duration: output.duration,
                transcript: output.transcript
            )
        } catch let error as TTSError {
            coordinator.errorMessage = error.localizedDescription
        } catch {
            coordinator.errorMessage = "Failed to generate speech: \(error.localizedDescription)"
        }

        isGenerating = false
        generationProgress = 0
    }

    /// Splits the input into batch segments and generates them sequentially.
    func startBatchGeneration() {
        guard let coordinator else { return }

        let segments = coordinator.batchSegments(from: coordinator.inputText)

        guard segments.count > 1 else {
            Task { await generateSpeech() }
            return
        }

        coordinator.stopPreview()

        let providerType = coordinator.selectedProvider
        let provider = coordinator.getProvider(for: providerType)
        let voice = coordinator.selectedVoice ?? provider.defaultVoice
        let voiceSnapshot = BatchGenerationItem.VoiceSnapshot(id: voice.id, name: voice.name)
        let format = coordinator.currentFormatForGeneration()

        batchTask?.cancel()
        batchItems = segments.enumerated().map { index, text in
            BatchGenerationItem(
                index: index + 1,
                text: text,
                provider: providerType,
                voice: voiceSnapshot
            )
        }

        batchProgress = 0
        isBatchRunning = true
        coordinator.errorMessage = nil
        coordinator.currentTranscript = nil

        batchTask = Task { [weak self] in
            await self?.processBatch(
                segments: segments,
                providerType: providerType,
                voice: voice,
                format: format
            )
        }
    }

    func cancelBatchGeneration() {
        guard batchTask != nil || isBatchRunning else { return }

        batchTask?.cancel()
        batchTask = nil
        isBatchRunning = false
        isGenerating = false
        generationProgress = 0
        batchProgress = 0

        batchItems = batchItems.map { item in
            var updated = item
            switch item.status {
            case .pending, .inProgress:
                updated.status = .failed("Cancelled")
            default:
                break
            }
            return updated
        }

        playback.stop()
    }
}
