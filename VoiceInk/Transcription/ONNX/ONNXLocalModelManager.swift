import AppKit
import Combine
import Foundation
import OSLog

/// Owns downloads and on-disk lifecycle for the community fork's ONNX speech models.
@MainActor
final class ONNXLocalModelManager: ObservableObject {
    static let shared = ONNXLocalModelManager()

    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published private(set) var activeDownloads: Set<String> = []

    private let fileManager: FileManager
    private let applicationSupportDirectory: URL
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "ONNXLocalModels")

    init(fileManager: FileManager = .default, applicationSupportDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? AppBrand.applicationSupportDirectory(using: fileManager)
    }

    func modelsDirectory(for provider: ModelProvider) -> URL {
        applicationSupportDirectory.appendingPathComponent(directoryName(for: provider), isDirectory: true)
    }

    func modelDirectory(for model: any TranscriptionModel) -> URL {
        modelsDirectory(for: model.provider).appendingPathComponent(model.name, isDirectory: true)
    }

    func isModelDownloaded(_ model: any TranscriptionModel) -> Bool {
        guard model.provider == .fastConformer || model.provider == .senseVoice else { return false }
        let directory = modelDirectory(for: model)
        return OnnxModelFileLocator.findModelFile(in: directory) != nil
            && fileManager.fileExists(atPath: directory.appendingPathComponent("tokens.txt").path)
    }

    func download(_ model: any TranscriptionModel) async {
        guard let sources = downloadSources(for: model), !activeDownloads.contains(model.name) else { return }

        activeDownloads.insert(model.name)
        downloadProgress[model.name] = 0
        defer {
            activeDownloads.remove(model.name)
            downloadProgress[model.name] = nil
        }

        do {
            let providerDirectory = modelsDirectory(for: model.provider)
            try fileManager.createDirectory(at: providerDirectory, withIntermediateDirectories: true)
            let stagingDirectory = providerDirectory.appendingPathComponent(".download-\(UUID().uuidString)")
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            defer {
                // Best-effort cleanup: a successful move removes this directory already.
                try? fileManager.removeItem(at: stagingDirectory)
            }

            let modelDownload = try await URLSession.shared.download(from: sources.modelURL)
            try fileManager.moveItem(
                at: modelDownload.0,
                to: stagingDirectory.appendingPathComponent(sources.modelFilename)
            )
            downloadProgress[model.name] = 0.9

            let tokenizerDownload = try await URLSession.shared.download(from: sources.tokenizerURL)
            try fileManager.moveItem(
                at: tokenizerDownload.0,
                to: stagingDirectory.appendingPathComponent("tokens.txt")
            )

            let destination = modelDirectory(for: model)
            if fileManager.fileExists(atPath: destination.path) {
                try deleteResolvedDirectory(destination, within: providerDirectory)
            }
            try fileManager.moveItem(at: stagingDirectory, to: destination)
            downloadProgress[model.name] = 1
            NotificationManager.shared.showNotification(
                title: String(format: String(localized: "%@ is ready"), model.displayName),
                type: .success
            )
        } catch {
            logger.error("ONNX model download failed for \(model.name, privacy: .public): \(AppLogger.errorMetadata(error), privacy: .public)")
            NotificationManager.shared.showNotification(
                title: String(format: String(localized: "Failed to download %@"), model.displayName),
                type: .error
            )
        }
    }

    func delete(_ model: any TranscriptionModel) throws {
        let root = modelsDirectory(for: model.provider)
        try deleteResolvedDirectory(modelDirectory(for: model), within: root)
        NotificationCenter.default.post(name: .didChangeModel, object: nil)
    }

    func showInFinder(_ model: any TranscriptionModel) {
        NSWorkspace.shared.activateFileViewerSelecting([modelDirectory(for: model)])
    }

    private func directoryName(for provider: ModelProvider) -> String {
        switch provider {
        case .fastConformer: return "FastConformerModels"
        case .senseVoice: return "SenseVoiceModels"
        default: return "ONNXModels"
        }
    }

    private func downloadSources(
        for model: any TranscriptionModel
    ) -> (modelURL: URL, tokenizerURL: URL, modelFilename: String)? {
        if let model = model as? FastConformerModel,
           let modelURL = URL(string: model.modelURL),
           let tokenizerURL = URL(string: model.tokenizerURL) {
            return (modelURL, tokenizerURL, "model.onnx")
        }
        if let model = model as? SenseVoiceModel,
           let modelURL = URL(string: model.modelURL),
           let tokenizerURL = URL(string: model.tokenizerURL) {
            return (modelURL, tokenizerURL, "model.int8.onnx")
        }
        return nil
    }

    private func deleteResolvedDirectory(_ directory: URL, within root: URL) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let confinedPrefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        guard resolvedDirectory.path.hasPrefix(confinedPrefix) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try fileManager.removeItem(at: resolvedDirectory)
    }
}
