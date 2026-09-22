import AudioToolbox
import Foundation

// MARK: - Error Types

enum CoreAudioRecorderError: LocalizedError {
    case audioUnitNotFound
    case audioUnitNotInitialized
    case deviceNotAvailable
    case failedToCreateAudioUnit(status: OSStatus)
    case failedToEnableInput(status: OSStatus)
    case failedToDisableOutput(status: OSStatus)
    case failedToSetDevice(status: OSStatus)
    case failedToGetDeviceFormat(status: OSStatus)
    case failedToSetFormat(status: OSStatus)
    case failedToSetCallback(status: OSStatus)
    case failedToCreateFile(status: OSStatus)
    case failedToSetFileFormat(status: OSStatus)
    case failedToInitialize(status: OSStatus)
    case failedToStart(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .audioUnitNotFound:
            return String(localized: "HAL Output AudioUnit not found")
        case .audioUnitNotInitialized:
            return String(localized: "AudioUnit not initialized")
        case .deviceNotAvailable:
            return String(localized: "Audio device is no longer available")
        case .failedToCreateAudioUnit(let status):
            return String(format: String(localized: "Failed to create AudioUnit: %lld"), Int64(status))
        case .failedToEnableInput(let status):
            return String(format: String(localized: "Failed to enable input: %lld"), Int64(status))
        case .failedToDisableOutput(let status):
            return String(format: String(localized: "Failed to disable output: %lld"), Int64(status))
        case .failedToSetDevice(let status):
            return String(format: String(localized: "Failed to set input device: %lld"), Int64(status))
        case .failedToGetDeviceFormat(let status):
            return String(format: String(localized: "Failed to get device format: %lld"), Int64(status))
        case .failedToSetFormat(let status):
            return String(format: String(localized: "Failed to set audio format: %lld"), Int64(status))
        case .failedToSetCallback(let status):
            return String(format: String(localized: "Failed to set input callback: %lld"), Int64(status))
        case .failedToCreateFile(let status):
            return String(format: String(localized: "Failed to create audio file: %lld"), Int64(status))
        case .failedToSetFileFormat(let status):
            return String(format: String(localized: "Failed to set file format: %lld"), Int64(status))
        case .failedToInitialize(let status):
            return String(format: String(localized: "Failed to initialize AudioUnit: %lld"), Int64(status))
        case .failedToStart(let status):
            return String(format: String(localized: "Failed to start AudioUnit: %lld"), Int64(status))
        }
    }
}
