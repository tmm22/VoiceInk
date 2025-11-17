import Foundation
import AppKit

extension WhisperState {
    private func fastConformerDefaultsKey(for modelName: String) -> String {
        "FastConformerModelDownloaded_\(modelName)"
    }

    func isFastConformerModelDownloaded(_ model: FastConformerModel) -> Bool {
        let directory = fastConformerModelDirectory(for: model)
        let modelFile = directory.appendingPathComponent("model.onnx")
        let tokenizerFile = directory.appendingPathComponent("tokens.txt")
        return FileManager.default.fileExists(atPath: modelFile.path) &&
            FileManager.default.fileExists(atPath: tokenizerFile.path)
    }

    private func fastConformerModelDirectory(for model: FastConformerModel) -> URL {
        fastConformerModelsDirectory.appendingPathComponent(model.name)
    }

    @MainActor
    func downloadFastConformerModel(_ model: FastConformerModel) async {
        if isFastConformerModelDownloaded(model) {
            return
        }

        fastConformerDownloadProgress[model.name] = 0.01

        let directory = fastConformerModelDirectory(for: model)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            guard let modelURL = URL(string: model.modelURL),
                  let tokenizerURL = URL(string: model.tokenizerURL) else {
                throw WhisperStateError.modelLoadFailed
            }

            let modelFile = directory.appendingPathComponent("model.onnx")
            let tokenizerFile = directory.appendingPathComponent("tokens.txt")

            try await downloadFileWithProgress(
                from: modelURL,
                to: modelFile,
                progressKey: model.name + "_fastconformer_model",
                progressUpdate: { [weak self] value in
                    Task { @MainActor in
                        self?.fastConformerDownloadProgress[model.name] = max(0.05, value * 0.85)
                    }
                }
            )

            try await downloadFileWithProgress(
                from: tokenizerURL,
                to: tokenizerFile,
                progressKey: model.name + "_fastconformer_tokens",
                progressUpdate: { [weak self] value in
                    Task { @MainActor in
                        let base = self?.fastConformerDownloadProgress[model.name] ?? 0.85
                        let finalProgress = min(0.85 + (value * 0.15), 0.99)
                        self?.fastConformerDownloadProgress[model.name] = max(base, finalProgress)
                    }
                }
            )

            downloadProgress.removeValue(forKey: model.name + "_fastconformer_model")
            downloadProgress.removeValue(forKey: model.name + "_fastconformer_tokens")
            fastConformerDownloadProgress[model.name] = 1.0
            UserDefaults.standard.set(true, forKey: fastConformerDefaultsKey(for: model.name))
            fastConformerTranscriptionService.invalidateSession(for: model.name)
            await NotificationManager.shared.showNotification(
                title: "FastConformer ready",
                type: .success,
                duration: 3.0
            )
        } catch {
            downloadProgress.removeValue(forKey: model.name + "_fastconformer_model")
            downloadProgress.removeValue(forKey: model.name + "_fastconformer_tokens")
            fastConformerDownloadProgress[model.name] = nil
            UserDefaults.standard.set(false, forKey: fastConformerDefaultsKey(for: model.name))
            await NotificationManager.shared.showNotification(
                title: "FastConformer download failed",
                type: .error,
                duration: 4.0
            )
        }
    }

    func deleteFastConformerModel(_ model: FastConformerModel) {
        let directory = fastConformerModelDirectory(for: model)
        try? FileManager.default.removeItem(at: directory)
        fastConformerDownloadProgress[model.name] = nil
        UserDefaults.standard.set(false, forKey: fastConformerDefaultsKey(for: model.name))
        fastConformerTranscriptionService.invalidateSession(for: model.name)
    }

    func showFastConformerModelInFinder(_ model: FastConformerModel) {
        let directory = fastConformerModelDirectory(for: model)
        if FileManager.default.fileExists(atPath: directory.path) {
            NSWorkspace.shared.selectFile(directory.path, inFileViewerRootedAtPath: "")
        }
    }
}
