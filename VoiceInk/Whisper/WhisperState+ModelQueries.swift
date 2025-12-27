import Foundation

extension WhisperState {
    var usableModels: [any TranscriptionModel] {
        return allAvailableModels.filter { model in
            ModelCapabilityRegistry.shared.isModelAvailable(model, whisperState: self)
        }
    }
}
