import Foundation
import Combine
import os

@MainActor
final class WhisperModelWarmupCoordinator: ObservableObject {
    static let shared = WhisperModelWarmupCoordinator()
    
    @Published private(set) var warmingModels: Set<String> = []
    
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "WhisperModelWarmupCoordinator")
    
    private init() {}
    
    func isWarming(modelNamed name: String) -> Bool {
        warmingModels.contains(name)
    }
    
    /// Schedule warmup using WhisperState (legacy interface for backward compatibility)
    func scheduleWarmup(for model: LocalModel, whisperState: WhisperState) {
        guard shouldWarmup(modelName: model.name),
              !warmingModels.contains(model.name) else {
            return
        }
        
        warmingModels.insert(model.name)
        
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.runWarmup(for: model, whisperState: whisperState)
            } catch {
                // No need for MainActor.run - this class is already @MainActor
                whisperState.logger.error("Warmup failed for \(model.name): \(error.localizedDescription)")
            }
            
            // No need for MainActor.run - this class is already @MainActor
            self.warmingModels.remove(model.name)
        }
    }
    
    /// Schedule warmup using LocalModelProvider (new interface)
    func scheduleWarmup(for model: LocalModel, localProvider: LocalModelProvider) {
        guard shouldWarmup(modelName: model.name),
              !warmingModels.contains(model.name) else {
            return
        }
        
        warmingModels.insert(model.name)
        
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.runWarmup(for: model, localProvider: localProvider)
            } catch {
                logger.error("Warmup failed for \(model.name): \(error.localizedDescription)")
            }
            
            self.warmingModels.remove(model.name)
        }
    }
    
    private func runWarmup(for model: LocalModel, whisperState: WhisperState) async throws {
        guard let sampleURL = warmupSampleURL() else { return }
        let service = LocalTranscriptionService(
            modelsDirectory: whisperState.modelsDirectory,
            whisperState: whisperState
        )
        _ = try await service.transcribe(audioURL: sampleURL, model: model)
    }
    
    private func runWarmup(for model: LocalModel, localProvider: LocalModelProvider) async throws {
        guard let sampleURL = warmupSampleURL() else { return }
        let service = LocalTranscriptionService(
            modelsDirectory: localProvider.modelsDirectory,
            localProvider: localProvider
        )
        _ = try await service.transcribe(audioURL: sampleURL, model: model)
    }
    
    private func warmupSampleURL() -> URL? {
        let bundle = Bundle.main
        let candidates: [URL?] = [
            bundle.url(forResource: "esc", withExtension: "wav", subdirectory: "Resources/Sounds"),
            bundle.url(forResource: "esc", withExtension: "wav", subdirectory: "Sounds"),
            bundle.url(forResource: "esc", withExtension: "wav")
        ]

        for candidate in candidates {
            if let url = candidate {
                return url
            }
        }

        return nil
    }
    
    private func shouldWarmup(modelName: String) -> Bool {
        !modelName.contains("q5") && !modelName.contains("q8")
    }
}
