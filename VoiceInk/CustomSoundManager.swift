import Foundation
import AVFoundation
import SwiftUI

@MainActor
class CustomSoundManager: ObservableObject {
    static let shared = CustomSoundManager()

    enum SoundType: String {
        case start
        case stop

        var isUsingKey: String { "isUsingCustom\(rawValue.capitalized)Sound" }
        var filenameKey: String { "custom\(rawValue.capitalized)SoundFilename" }
        var standardName: String { "Custom\(rawValue.capitalized)Sound" }
    }

    @Published var isUsingCustomStartSound: Bool {
        didSet { AppSettings.setValue(isUsingCustomStartSound, forKey: SoundType.start.isUsingKey) }
    }

    @Published var isUsingCustomStopSound: Bool {
        didSet { AppSettings.setValue(isUsingCustomStopSound, forKey: SoundType.stop.isUsingKey) }
    }

    private let maxSoundDuration: TimeInterval = 3.0

    private var customStartSoundFilename: String? {
        didSet { updateFilenameInUserDefaults(filename: customStartSoundFilename, for: .start) }
    }

    private var customStopSoundFilename: String? {
        didSet { updateFilenameInUserDefaults(filename: customStopSoundFilename, for: .stop) }
    }
    
    private func updateFilenameInUserDefaults(filename: String?, for type: SoundType) {
        if let filename = filename {
            AppSettings.setValue(filename, forKey: type.filenameKey)
        } else {
            AppSettings.removeValue(forKey: type.filenameKey)
        }
    }

    private init() {
        self.isUsingCustomStartSound = AppSettings.bool(forKey: SoundType.start.isUsingKey, default: false)
        self.isUsingCustomStopSound = AppSettings.bool(forKey: SoundType.stop.isUsingKey, default: false)
        let startFilename = AppSettings.string(forKey: SoundType.start.filenameKey, default: "")
        let stopFilename = AppSettings.string(forKey: SoundType.stop.filenameKey, default: "")
        self.customStartSoundFilename = startFilename.isEmpty ? nil : startFilename
        self.customStopSoundFilename = stopFilename.isEmpty ? nil : stopFilename

        createCustomSoundsDirectoryIfNeeded()
    }

    private func customSoundsDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("VoiceInk/CustomSounds")
    }

    private func createCustomSoundsDirectoryIfNeeded() {
        guard let directory = customSoundsDirectory() else { return }

        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                AppLogger.storage.error("Failed to create custom sounds directory: \(error.localizedDescription)")
            }
        }
    }

    func getCustomSoundURL(for type: SoundType) -> URL? {
        let isUsing = (type == .start) ? isUsingCustomStartSound : isUsingCustomStopSound
        let filename = (type == .start) ? customStartSoundFilename : customStopSoundFilename
        
        guard isUsing, let filename = filename, let directory = customSoundsDirectory() else {
            return nil
        }
        return directory.appendingPathComponent(filename)
    }

    func setCustomSound(url: URL, for type: SoundType) -> Result<Void, CustomSoundError> {
        let result = validateAudioFile(url: url)
        switch result {
        case .success:
            let copyResult = copySoundFile(from: url, standardName: type.standardName)
            switch copyResult {
            case .success(let filename):
                if type == .start {
                    customStartSoundFilename = filename
                    isUsingCustomStartSound = true
                } else {
                    customStopSoundFilename = filename
                    isUsingCustomStopSound = true
                }
                notifyCustomSoundsChanged()
                return .success(())
            case .failure(let error):
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    func resetSoundToDefault(for type: SoundType) {
        let filename = (type == .start) ? customStartSoundFilename : customStopSoundFilename
        
        if let filename = filename, let directory = customSoundsDirectory() {
            let fileURL = directory.appendingPathComponent(filename)
            // Best-effort cleanup; file may already be removed.
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        if type == .start {
            isUsingCustomStartSound = false
            customStartSoundFilename = nil
        } else {
            isUsingCustomStopSound = false
            customStopSoundFilename = nil
        }
        notifyCustomSoundsChanged()
    }

    private func notifyCustomSoundsChanged() {
        NotificationCenter.default.post(name: NSNotification.Name("CustomSoundsChanged"), object: nil)
    }

    func getSoundDisplayName(for type: SoundType) -> String? {
        return (type == .start) ? customStartSoundFilename : customStopSoundFilename
    }

    private func copySoundFile(from sourceURL: URL, standardName: String) -> Result<String, CustomSoundError> {
        guard let directory = customSoundsDirectory() else {
            return .failure(.directoryCreationFailed)
        }

        let fileExtension = sourceURL.pathExtension
        let newFilename = "\(standardName).\(fileExtension)"
        let destinationURL = directory.appendingPathComponent(newFilename)

        if sourceURL.resolvingSymlinksInPath() == destinationURL.resolvingSymlinksInPath() {
            return .success(newFilename)
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return .success(newFilename)
        } catch {
            return .failure(.fileCopyFailed)
        }
    }

    private func validateAudioFile(url: URL) -> Result<Void, CustomSoundError> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.fileNotFound)
        }

        let duration: TimeInterval
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let sampleRate = audioFile.fileFormat.sampleRate
            guard sampleRate > 0 else {
                return .failure(.invalidAudioFile)
            }
            duration = Double(audioFile.length) / sampleRate
        } catch {
            return .failure(.invalidAudioFile)
        }

        guard duration.isFinite && duration > 0 else {
            return .failure(.invalidAudioFile)
        }

        if duration > maxSoundDuration {
            return .failure(.durationTooLong(duration: duration, maxDuration: maxSoundDuration))
        }

        do {
            _ = try AVAudioPlayer(contentsOf: url)
        } catch {
            return .failure(.invalidAudioFile)
        }

        return .success(())
    }
}

enum CustomSoundError: LocalizedError {
    case fileNotFound
    case invalidAudioFile
    case durationTooLong(duration: TimeInterval, maxDuration: TimeInterval)
    case directoryCreationFailed
    case fileCopyFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .invalidAudioFile:
            return "Invalid audio file format"
        case .durationTooLong(let duration, let maxDuration):
            return String(format: "Audio file is %.1f seconds long. Please use an audio file that is %.0f seconds or shorter for start and stop sounds.", duration, maxDuration)
        case .directoryCreationFailed:
            return "Failed to create custom sounds directory"
        case .fileCopyFailed:
            return "Failed to copy audio file"
        }
    }
}
