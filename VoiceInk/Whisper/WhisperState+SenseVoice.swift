import Foundation
import AppKit

extension WhisperState {
    private func senseVoiceDefaultsKey(for modelName: String) -> String {
        "SenseVoiceModelDownloaded_\(modelName)"
    }

    func isSenseVoiceModelDownloaded(_ model: SenseVoiceModel) -> Bool {
        let directory = senseVoiceModelDirectory(for: model)
        let modelFile = directory.appendingPathComponent("model.int8.onnx")
        let tokenizerFile = directory.appendingPathComponent("tokens.txt")
        return FileManager.default.fileExists(atPath: modelFile.path) &&
            FileManager.default.fileExists(atPath: tokenizerFile.path)
    }

    private func senseVoiceModelDirectory(for model: SenseVoiceModel) -> URL {
        senseVoiceModelsDirectory.appendingPathComponent(model.name)
    }

    @MainActor
    func downloadSenseVoiceModel(_ model: SenseVoiceModel) async {
        if isSenseVoiceModelDownloaded(model) {
            return
        }

        senseVoiceDownloadProgress[model.name] = 0.01

        let directory = senseVoiceModelDirectory(for: model)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            guard let modelURL = URL(string: model.modelURL),
                  let tokenizerURL = URL(string: model.tokenizerURL) else {
                throw WhisperStateError.modelLoadFailed
            }

            let modelFile = directory.appendingPathComponent("model.int8.onnx")
            let tokenizerFile = directory.appendingPathComponent("tokens.txt")

            try await downloadFileWithProgress(
                from: modelURL,
                to: modelFile,
                progressKey: model.name + "_sensevoice_model",
                progressUpdate: { [weak self] value in
                    Task { @MainActor in
                        self?.senseVoiceDownloadProgress[model.name] = max(0.05, value * 0.85)
                    }
                }
            )

            try await downloadFileWithProgress(
                from: tokenizerURL,
                to: tokenizerFile,
                progressKey: model.name + "_sensevoice_tokens",
                progressUpdate: { [weak self] value in
                    Task { @MainActor in
                        let base = self?.senseVoiceDownloadProgress[model.name] ?? 0.85
                        let finalProgress = min(0.85 + (value * 0.15), 0.99)
                        self?.senseVoiceDownloadProgress[model.name] = max(base, finalProgress)
                    }
                }
            )

            downloadProgress.removeValue(forKey: model.name + "_sensevoice_model")
            downloadProgress.removeValue(forKey: model.name + "_sensevoice_tokens")
            senseVoiceDownloadProgress[model.name] = 1.0
            AppSettings.setValue(true, forKey: senseVoiceDefaultsKey(for: model.name))
            senseVoiceTranscriptionService.invalidateSession(for: model.name)
            NotificationManager.shared.showNotification(
                title: Localization.Models.downloadSuccess,
                type: .success,
                duration: 3.0
            )
        } catch {
            downloadProgress.removeValue(forKey: model.name + "_sensevoice_model")
            downloadProgress.removeValue(forKey: model.name + "_sensevoice_tokens")
            senseVoiceDownloadProgress[model.name] = nil
            AppSettings.setValue(false, forKey: senseVoiceDefaultsKey(for: model.name))
            NotificationManager.shared.showNotification(
                title: Localization.Models.downloadFailed,
                type: .error,
                duration: 4.0
            )
        }
    }

    @MainActor
    func deleteSenseVoiceModel(_ model: SenseVoiceModel) {
        // Clear current selection if this model is active
        if let currentModel = currentTranscriptionModel,
           currentModel.provider == .senseVoice,
           currentModel.name == model.name {
            currentTranscriptionModel = nil
            AppSettings.TranscriptionSettings.currentTranscriptionModel = nil
        }
        
        let directory = senseVoiceModelDirectory(for: model)
        try? FileManager.default.removeItem(at: directory)
        senseVoiceDownloadProgress[model.name] = nil
        AppSettings.setValue(false, forKey: senseVoiceDefaultsKey(for: model.name))
        senseVoiceTranscriptionService.invalidateSession(for: model.name)
    }

    func showSenseVoiceModelInFinder(_ model: SenseVoiceModel) {
        let directory = senseVoiceModelDirectory(for: model)
        if FileManager.default.fileExists(atPath: directory.path) {
            NSWorkspace.shared.selectFile(directory.path, inFileViewerRootedAtPath: "")
        }
    }
}
