import SwiftUI
import AVFoundation

/// Manages transcription recording and post-processing for the TTS workspace.
@MainActor
final class TTSTranscriptionViewModel: ObservableObject {
    @Published var selectedTranscriptionProvider: TranscriptionProviderType {
        didSet {
            guard selectedTranscriptionProvider != oldValue else { return }
            if transcriptionServices[selectedTranscriptionProvider] == nil {
                selectedTranscriptionProvider = defaultProvider
                return
            }
            if hasLoadedInitialSettings {
                AppSettings.Transcription.selectedProviderRawValue = selectedTranscriptionProvider.rawValue
            }
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

    private let transcriptionServices: [TranscriptionProviderType: any AudioTranscribing]
    private let defaultProvider: TranscriptionProviderType
    private let transcriptInsightsService: TranscriptInsightsServicing
    private let transcriptCleanupService: TranscriptCleanupServicing
    private let transcriptionRecorder: TranscriptionRecorder
    private let onInsertText: (String) -> Void

    private var transcriptionTask: Task<Void, Never>?
    private var transcriptionRecordingTimer: Timer?
    private var transcriptionRecordingStart: Date?
    private var transcriptionRecordingURL: URL?
    private var ephemeralRecordingURLs: Set<URL> = []
    private var hasLoadedInitialSettings = false

    init(
        transcriptionServices: [TranscriptionProviderType: any AudioTranscribing],
        defaultProvider: TranscriptionProviderType,
        transcriptInsightsService: TranscriptInsightsServicing,
        transcriptCleanupService: TranscriptCleanupServicing,
        transcriptionRecorder: TranscriptionRecorder = TranscriptionRecorder(),
        onInsertText: @escaping (String) -> Void
    ) {
        self.transcriptionServices = transcriptionServices
        self.defaultProvider = defaultProvider
        self.transcriptInsightsService = transcriptInsightsService
        self.transcriptCleanupService = transcriptCleanupService
        self.transcriptionRecorder = transcriptionRecorder
        self.onInsertText = onInsertText
        self.selectedTranscriptionProvider = defaultProvider
        loadSavedProvider()
    }

    deinit {
        transcriptionTask?.cancel()
        transcriptionRecordingTimer?.invalidate()
        transcriptionRecordingTimer = nil
    }

    // MARK: - Public API
    func setTranscriptionCleanupPreset(instruction: String, label: String?) {
        transcriptionCleanupInstruction = instruction
        transcriptionCleanupLabel = label
    }

    func clearTranscriptionCleanupPreset() {
        transcriptionCleanupInstruction = ""
        transcriptionCleanupLabel = nil
    }

    func startTranscriptionRecording() {
        guard !isTranscriptionRecording else { return }

        transcriptionTask?.cancel()
        transcriptionError = nil

        if let existingURL = transcriptionRecordingURL {
            let standardizedExisting = existingURL.standardizedFileURL
            ephemeralRecordingURLs.remove(standardizedExisting)
            // Best-effort cleanup; stale temp file may already be gone.
            try? FileManager.default.removeItem(at: standardizedExisting)
            transcriptionRecordingURL = nil
        }

        transcriptionRecordingDuration = 0
        transcriptionRecordingLevel = 0
        transcriptionStage = .recording
        isTranscriptionInProgress = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let url = try await self.transcriptionRecorder.startRecording()
                let standardizedURL = url.standardizedFileURL
                self.ephemeralRecordingURLs.insert(standardizedURL)
                self.transcriptionRecordingURL = standardizedURL
                self.transcriptionRecordingDuration = 0
                self.transcriptionRecordingLevel = 0
                self.transcriptionRecordingStart = Date()
                self.isTranscriptionRecording = true
                self.startRecordingTimer()
            } catch let error as TTSError {
                self.transcriptionError = error.localizedDescription
                self.transcriptionStage = .idle
                self.isTranscriptionInProgress = false
            } catch {
                self.transcriptionError = error.localizedDescription
                self.transcriptionStage = .idle
                self.isTranscriptionInProgress = false
            }
        }
    }

    func stopTranscriptionRecording() {
        guard isTranscriptionRecording else { return }
        let url = transcriptionRecorder.stopRecording()
        finishRecordingSession(with: url, shouldTranscribe: true)
    }

    func cancelTranscriptionRecording() {
        guard isTranscriptionRecording else { return }
        let url = transcriptionRecorder.cancelRecording()
        finishRecordingSession(with: url, shouldTranscribe: false)
        transcriptionStage = .idle
        transcriptionError = nil
    }

    /// Kick off transcription for a file, with optional cleanup and editor insertion.
    func transcribeAudioFile(at url: URL,
                             title: String? = nil,
                             languageHint: String? = nil,
                             shouldDeleteAfterTranscription: Bool? = nil,
                             autoInsertIntoEditor: Bool = false) {
        transcriptionTask?.cancel()
        let standardizedURL = url.standardizedFileURL
        let resolvedTitle = title ?? standardizedURL.deletingPathExtension().lastPathComponent
        let tempDirectoryPath = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let removedEphemeral = ephemeralRecordingURLs.remove(standardizedURL) != nil
        let shouldDeleteSource: Bool
        if let override = shouldDeleteAfterTranscription {
            shouldDeleteSource = override
        } else if removedEphemeral {
            shouldDeleteSource = true
        } else {
            shouldDeleteSource = standardizedURL.path.hasPrefix(tempDirectoryPath)
        }
        transcriptionTask = Task { [weak self] in
            await self?.executeTranscription(at: standardizedURL,
                                             title: resolvedTitle,
                                             languageHint: languageHint,
                                             shouldDeleteSource: shouldDeleteSource,
                                             autoInsertIntoEditor: autoInsertIntoEditor)
        }
    }

    func insertTranscriptionIntoEditor(useCleanedText: Bool) {
        guard let record = transcriptionRecord else { return }
        let candidate: String?
        if useCleanedText {
            candidate = transcriptionCleanupResult?.output
        } else {
            candidate = record.transcript
        }

        guard let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        onInsertText(text)
    }

    func transcriptionProviderHasCredentials(_ provider: TranscriptionProviderType) -> Bool {
        transcriptionServices[provider]?.hasCredentials() ?? false
    }

    func loadSavedProvider() {
        if let savedTranscriptionProvider = AppSettings.Transcription.selectedProviderRawValue,
           let provider = TranscriptionProviderType(rawValue: savedTranscriptionProvider),
           transcriptionServices[provider] != nil {
            selectedTranscriptionProvider = provider
        } else {
            selectedTranscriptionProvider = defaultProvider
        }
        hasLoadedInitialSettings = true
    }

    // MARK: - Private Helpers
    private func executeTranscription(at url: URL,
                                      title: String,
                                      languageHint: String?,
                                      shouldDeleteSource: Bool,
                                      autoInsertIntoEditor: Bool) async {
        resetTranscriptionState()
        isTranscriptionInProgress = true
        transcriptionStage = .transcribing
        transcriptionProgress = 0.15
        defer {
            isTranscriptionInProgress = false
            transcriptionTask = nil
            if shouldDeleteSource {
                // Best-effort cleanup; source may have been deleted by caller.
                try? FileManager.default.removeItem(at: url)
            }
        }

        do {
            let service = resolvedTranscriptionService()
            let transcription = try await service.transcribe(fileURL: url, languageHint: languageHint)
            try Task.checkCancellation()

            transcriptionText = transcription.text
            transcriptionLanguage = transcription.language
            transcriptionSegments = transcription.segments
            transcriptionProgress = 0.45

            transcriptionStage = .summarising
            let insights = try await transcriptInsightsService.generateInsights(for: transcription.text)
            try Task.checkCancellation()
            let meaningfulSummary = insights.isMeaningful ? insights : nil
            transcriptionSummary = meaningfulSummary
            transcriptionProgress = 0.7

            var cleanupResult: TranscriptCleanupResult?
            let trimmedInstruction = transcriptionCleanupInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedInstruction.isEmpty {
                transcriptionStage = .cleaning
                cleanupResult = try await transcriptCleanupService.clean(transcript: transcription.text,
                                                                          instruction: trimmedInstruction,
                                                                          label: transcriptionCleanupLabel)
                try Task.checkCancellation()
                transcriptionCleanupResult = cleanupResult
                transcriptionProgress = 0.9
            } else {
                transcriptionCleanupResult = nil
            }

            transcriptionRecord = TranscriptionRecord(
                title: title,
                transcript: transcription.text,
                language: transcription.language,
                duration: transcription.duration,
                segments: transcription.segments,
                summary: meaningfulSummary,
                cleanup: cleanupResult
            )

            if autoInsertIntoEditor {
                autoInsertTranscriptionIntoEditor(cleanupResult: cleanupResult, rawTranscript: transcription.text)
            }

            transcriptionStage = .complete
            transcriptionProgress = 1.0
            transcriptionError = nil
        } catch is CancellationError {
            // No-op: task cancelled by caller
        } catch let error as TTSError {
            transcriptionError = error.localizedDescription
            transcriptionStage = .error
        } catch {
            transcriptionError = error.localizedDescription
            transcriptionStage = .error
        }
    }

    private func resetTranscriptionState() {
        transcriptionStage = .idle
        transcriptionProgress = 0
        transcriptionSegments = []
        transcriptionSummary = nil
        transcriptionCleanupResult = nil
        transcriptionError = nil
        transcriptionRecord = nil
        transcriptionText = ""
        transcriptionLanguage = nil
    }

    private func autoInsertTranscriptionIntoEditor(cleanupResult: TranscriptCleanupResult?, rawTranscript: String) {
        if let cleaned = cleanupResult?.output.trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty {
            onInsertText(cleaned)
            return
        }

        let trimmedRaw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRaw.isEmpty {
            onInsertText(trimmedRaw)
        }
    }

    private func startRecordingTimer() {
        stopRecordingTimer()
        transcriptionRecordingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshRecordingMetrics()
            }
        }
        if let timer = transcriptionRecordingTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopRecordingTimer() {
        transcriptionRecordingTimer?.invalidate()
        transcriptionRecordingTimer = nil
    }

    private func refreshRecordingMetrics() {
        guard isTranscriptionRecording else { return }
        if let start = transcriptionRecordingStart {
            transcriptionRecordingDuration = Date().timeIntervalSince(start)
        }
        transcriptionRecordingLevel = transcriptionRecorder.currentLevel()
    }

    private func finishRecordingSession(with url: URL?, shouldTranscribe: Bool) {
        stopRecordingTimer()
        let finalDuration = transcriptionRecordingDuration
        transcriptionRecordingStart = nil
        transcriptionRecordingLevel = 0
        isTranscriptionRecording = false
        let previousRecordingURL = transcriptionRecordingURL

        if shouldTranscribe, let url {
            transcriptionRecordingDuration = finalDuration
            transcriptionRecordingURL = nil
            transcribeAudioFile(at: url, autoInsertIntoEditor: true)
        } else {
            transcriptionRecordingDuration = 0
            transcriptionRecordingURL = nil
            isTranscriptionInProgress = false
            if let url {
                let standardizedURL = url.standardizedFileURL
                ephemeralRecordingURLs.remove(standardizedURL)
                // Best-effort cleanup; recording may already be removed.
                try? FileManager.default.removeItem(at: standardizedURL)
            } else if let previousRecordingURL {
                ephemeralRecordingURLs.remove(previousRecordingURL.standardizedFileURL)
            }
        }
    }

    private func resolvedTranscriptionService() -> any AudioTranscribing {
        if let service = transcriptionServices[selectedTranscriptionProvider] {
            return service
        }
        if let fallback = transcriptionServices[defaultProvider] {
            return fallback
        }

        // Last resort: return any available service or a placeholder
        if let service = transcriptionServices.values.first {
            return service
        }

        // Critical error: no services available, but don't crash the app
        #if DEBUG
        print("No transcription services configured - returning placeholder")
        #endif

        return PlaceholderTranscriptionService()
    }

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
}

// Placeholder service for graceful degradation
private class PlaceholderTranscriptionService: AudioTranscribing {
    func hasCredentials() -> Bool {
        false
    }

    func transcribe(fileURL: URL, languageHint: String?) async throws -> (text: String, language: String?, duration: TimeInterval, segments: [TranscriptionSegment]) {
        throw TTSError.apiError("No transcription service is currently configured. Please check your settings.")
    }
}
