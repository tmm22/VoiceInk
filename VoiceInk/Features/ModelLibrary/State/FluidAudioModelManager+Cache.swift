import FluidAudio
import Foundation

extension FluidAudioModelManager {
    nonisolated static func parakeetRepo(for version: AsrModelVersion) -> Repo? {
        switch version {
        case .v2:
            return .parakeetV2
        case .v3:
            return .parakeetV3
        case .ultra:
            return .parakeetUltra
        default:
            return nil
        }
    }

    nonisolated static var parakeetUnifiedRequiredFiles: Set<String> {
        ModelNames.ParakeetUnified.requiredModels(variant: parakeetUnifiedStreamingVariant)
            .union(ModelNames.ParakeetUnified.requiredModels(variant: parakeetUnifiedOfflineVariant))
            .union([parakeetUnifiedStreamingEncoderFile])
    }

    nonisolated static func vadModelFilesExist() -> Bool {
        modelFileIsReady(at: vadModelURL)
    }

    nonisolated static var vadModelURL: URL {
        fluidAudioModelsRootDirectory()
            .appendingPathComponent(Repo.vad.folderName, isDirectory: true)
            .appendingPathComponent(ModelNames.VAD.sileroVadFile, isDirectory: true)
    }

    // Match FluidAudio's load-ready check so preserved partial downloads stay retryable.
    nonisolated static func modelFileIsReady(at url: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        guard url.pathExtension == "mlmodelc" else { return true }
        guard isDirectory.boolValue,
            fileManager.fileExists(atPath: url.appendingPathComponent("coremldata.bin").path),
            let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil)
        else { return false }

        for case let file as URL in enumerator where file.pathExtension == "partial" {
            return false
        }
        return true
    }

    nonisolated static func nemotronRequiredFilesExist(in directory: URL) -> Bool {
        let requiredFiles = [
            ModelNames.NemotronMultilingualStreaming.metadata,
            ModelNames.NemotronMultilingualStreaming.tokenizer,
            ModelNames.NemotronMultilingualStreaming.encoderFile,
        ]

        let requiredFilesExist = requiredFiles.allSatisfy {
            modelFileIsReady(at: directory.appendingPathComponent($0))
        }
        guard requiredFilesExist else { return false }

        let hasFusedDecoder = [
            "decoder_joint_argmax.mlmodelc",
            "decoder_joint_noencproj.mlmodelc",
            "decoder_joint.mlmodelc",
        ].contains { modelFileIsReady(at: directory.appendingPathComponent($0)) }
        let hasBareDecoderAndJoint =
            modelFileIsReady(
                at: directory.appendingPathComponent(ModelNames.NemotronMultilingualStreaming.decoderFile)
            )
            && modelFileIsReady(
                at: directory.appendingPathComponent(ModelNames.NemotronMultilingualStreaming.jointFile)
            )

        return hasFusedDecoder || hasBareDecoderAndJoint
    }

    nonisolated static func parakeetUnifiedCacheDirectory() -> URL {
        fluidAudioModelsRootDirectory()
            .appendingPathComponent(Repo.parakeetUnified.folderName, isDirectory: true)
    }

    // Matches the cache root used by FluidAudio's Unified managers.
    nonisolated static func fluidAudioModelsRootDirectory() -> URL {
        let fileManager = FileManager.default
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return
                appSupport
                .appendingPathComponent("FluidAudio", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
        }

        return fileManager.temporaryDirectory
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }
}
