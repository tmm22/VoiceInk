import Foundation
import AVFoundation
import os
import SwiftUI

/// Main processor for handling transcription requests
@MainActor
class TranscriptionProcessor: ObservableObject, TranscriptionProcessorProtocol {
    // MARK: - Properties
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "TranscriptionProcessor")

    @Published var isProcessing = false

    // Dependencies
    private var audioPreprocessor: AudioPreprocessor?
    private var resultProcessor: TranscriptionResultProcessor?

    // Services will be injected via a service registry to avoid circular dependencies
    private var serviceRegistry: [String: any TranscriptionService] = [:]

    // Enhancement services
    private weak var enhancementService: AIEnhancementService?
    private weak var promptDetectionService: PromptDetectionService?

    // State
    private var currentTask: Task<TranscriptionResult, Error>?

    // MARK: - Initialization
    init() {
        // Dependencies are initialized lazily to avoid main actor isolation issues
        initializeDependencies()
    }

    private func initializeDependencies() {
        self.audioPreprocessor = AudioPreprocessor()
        self.resultProcessor = TranscriptionResultProcessor()
    }

    /// Register a transcription service for a specific provider
    func registerService(_ service: any TranscriptionService, for provider: String) {
        serviceRegistry[provider] = service
    }

    /// Configure enhancement and prompt detection services
    func configure(enhancementService: AIEnhancementService?, promptDetectionService: PromptDetectionService?) {
        self.enhancementService = enhancementService
        self.promptDetectionService = promptDetectionService
    }

    // MARK: - TranscriptionProcessorProtocol

    func transcribe(audioData: Data, languageHint: String?) async throws -> TranscriptionResult {
        guard !isProcessing else {
            throw TranscriptionProcessorError.alreadyProcessing
        }

        isProcessing = true
        defer { isProcessing = false }

        logger.info("🔄 Starting transcription processing")

        // This method expects audio data, but we need to work with URLs in the current architecture
        // For now, we'll throw an error indicating this needs to be adapted
        throw TranscriptionProcessorError.notImplemented("Direct audio data processing not yet implemented")
    }

    func cancelTranscription() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        logger.info("🛑 Transcription cancelled")
    }

    // MARK: - Public Methods

    /// Process transcription from audio URL (main entry point)
    func processTranscription(
        audioURL: URL,
        model: any TranscriptionModel,
        languageHint: String? = nil
    ) async throws -> TranscriptionResult {
        guard !isProcessing else {
            throw TranscriptionProcessorError.alreadyProcessing
        }

        let task = Task {
            do {
                isProcessing = true
                defer { isProcessing = false }

                return try await performTranscription(audioURL: audioURL, model: model, languageHint: languageHint)
            } catch {
                isProcessing = false
                throw error
            }
        }

        currentTask = task
        return try await task.value
    }

    // MARK: - Private Methods

    private func performTranscription(
        audioURL: URL,
        model: any TranscriptionModel,
        languageHint: String?
    ) async throws -> TranscriptionResult {
        guard let audioPreprocessor = audioPreprocessor,
              let resultProcessor = resultProcessor else {
            throw TranscriptionProcessorError.notImplemented("Dependencies not initialized")
        }

        logger.info("🔄 Processing transcription for model: \(model.displayName)")

        // Preprocess audio
        let (audioData, duration) = try await audioPreprocessor.preprocessAudio(from: audioURL)

        // Select appropriate transcription service
        let service = try selectTranscriptionService(for: model)

        // Perform transcription
        let transcriptionStart = Date()
        let rawText = try await service.transcribe(audioURL: audioURL, model: model)
        let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)

        logger.info("📝 Raw transcription: \(rawText, privacy: .public)")

        // Process result
        let (processedText, actualDuration) = try await resultProcessor.processResult(
            rawText: rawText,
            audioURL: audioURL,
            modelName: model.displayName,
            transcriptionDuration: transcriptionDuration
        )

        // Create basic result (enhanced features will be added later)
        let result = resultProcessor.createTranscriptionResult(
            text: processedText,
            enhancedText: nil,
            duration: actualDuration,
            transcriptionDuration: transcriptionDuration,
            enhancementDuration: nil,
            modelName: model.displayName,
            promptName: nil,
            powerModeName: nil,
            powerModeEmoji: nil,
            aiRequestSystemMessage: nil,
            aiRequestUserMessage: nil,
            aiContextJSON: nil,
            aiEnhancementModelName: nil
        )

        logger.info("✅ Transcription processing complete")
        return result
    }

    private func selectTranscriptionService(for model: any TranscriptionModel) throws -> any TranscriptionService {
        let providerKey = model.provider.rawValue
        guard let service = serviceRegistry[providerKey] else {
            throw TranscriptionProcessorError.serviceUnavailable(model.provider)
        }
        return service
    }
}

// MARK: - Error Types
enum TranscriptionProcessorError: LocalizedError {
    case alreadyProcessing
    case serviceUnavailable(ModelProvider)
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .alreadyProcessing:
            return "Transcription is already in progress"
        case .serviceUnavailable(let provider):
            return "Transcription service for \(provider.rawValue) is not available"
        case .notImplemented(let feature):
            return "Feature not implemented: \(feature)"
        }
    }
}