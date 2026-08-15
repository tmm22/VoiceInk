import AVFoundation
import Foundation

enum SoundFileStoreError: LocalizedError {
    case unsupportedFormat
    case invalidAudio
    case fileTooLarge
    case durationTooLong
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return String(localized: "Choose an MP3, WAV, or AIFF audio file.")
        case .invalidAudio:
            return String(localized: "The selected file is not valid audio.")
        case .fileTooLarge:
            return String(localized: "The selected sound file is too large.")
        case .durationTooLong:
            return String(localized: "Choose a sound that is three seconds or shorter.")
        case .storageUnavailable:
            return String(localized: "VoiceInk could not store the selected sound.")
        }
    }
}

actor SoundFileStore {
    private let allowedExtensions: Set<String> = ["mp3", "wav", "aif", "aiff"]
    private let maximumFileSize = 20 * 1_024 * 1_024
    private let maximumDuration: TimeInterval = 3

    func importSound(from sourceURL: URL, type: SoundType) async throws -> URL {
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard allowedExtensions.contains(fileExtension) else {
            throw SoundFileStoreError.unsupportedFormat
        }

        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw SoundFileStoreError.invalidAudio }
        guard (values.fileSize ?? 0) <= maximumFileSize else { throw SoundFileStoreError.fileTooLarge }

        let duration = try await AVURLAsset(url: sourceURL).load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw SoundFileStoreError.invalidAudio }
        guard duration <= maximumDuration else { throw SoundFileStoreError.durationTooLong }
        guard (try? AVAudioPlayer(contentsOf: sourceURL)) != nil else {
            throw SoundFileStoreError.invalidAudio
        }

        let directory = try storageDirectory()
        try removeStoredSounds(for: type, in: directory)
        let destinationURL = directory.appendingPathComponent("\(type.storageName).\(fileExtension)")
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            throw SoundFileStoreError.storageUnavailable
        }
    }

    func removeStoredSound(at url: URL?) {
        guard let url, isInsideStorage(url) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            AppLogger.audio.warning(
                "Failed to remove a stored custom sound: \(AppLogger.errorMetadata(error), privacy: .public)"
            )
        }
    }

    private func storageDirectory() throws -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SoundFileStoreError.storageUnavailable
        }
        let directory = appSupport
            .appendingPathComponent("VoiceInk", isDirectory: true)
            .appendingPathComponent("CustomSounds", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            throw SoundFileStoreError.storageUnavailable
        }
    }

    private func removeStoredSounds(for type: SoundType, in directory: URL) throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for url in urls where url.deletingPathExtension().lastPathComponent == type.storageName {
            guard isInsideStorage(url) else { continue }
            try FileManager.default.removeItem(at: url)
        }
    }

    private func isInsideStorage(_ url: URL) -> Bool {
        guard let directory = try? storageDirectory() else { return false }
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path.hasPrefix(prefix)
    }
}
