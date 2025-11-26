import Foundation

enum AudioPreset: String, Codable, CaseIterable {
    case `default` = "Default"
    case minimal = "Minimal"
    case classic = "Classic"
    case modern = "Modern"
    case silent = "Silent"
    
    var displayName: String { rawValue }
    
    var soundFiles: SoundFiles {
        switch self {
        case .default:
            return SoundFiles(
                start: "recstart.mp3",
                stop: "recstop.mp3",
                cancel: "esc.wav"
            )
        case .minimal:
            return SoundFiles(
                start: "minimal-start.wav",
                stop: "minimal-stop.wav",
                cancel: "minimal-cancel.wav"
            )
        case .classic:
            return SoundFiles(
                start: "classic-start.wav",
                stop: "classic-stop.wav",
                cancel: "classic-cancel.wav"
            )
        case .modern:
            return SoundFiles(
                start: "modern-start.wav",
                stop: "modern-stop.wav",
                cancel: "modern-cancel.wav"
            )
        case .silent:
            return SoundFiles(start: nil, stop: nil, cancel: nil)
        }
    }
    
    var defaultVolumes: SoundVolumes {
        switch self {
        case .default:
            return SoundVolumes(start: 0.4, stop: 0.4, cancel: 0.3)
        case .minimal:
            return SoundVolumes(start: 0.3, stop: 0.3, cancel: 0.2)
        case .classic:
            return SoundVolumes(start: 0.5, stop: 0.5, cancel: 0.4)
        case .modern:
            return SoundVolumes(start: 0.4, stop: 0.4, cancel: 0.3)
        case .silent:
            return SoundVolumes(start: 0.0, stop: 0.0, cancel: 0.0)
        }
    }
}

struct SoundFiles: Codable, Equatable {
    var start: String?
    var stop: String?
    var cancel: String?
}

struct SoundVolumes: Codable {
    var start: Float
    var stop: Float
    var cancel: Float
    
    static let `default` = SoundVolumes(start: 0.4, stop: 0.4, cancel: 0.3)
}

struct CustomSounds: Codable {
    var startPath: String?
    var stopPath: String?
    var cancelPath: String?
}

struct AudioFeedbackSettings: Codable {
    var preset: AudioPreset
    var customSounds: CustomSounds?
    var volumes: SoundVolumes
    var isEnabled: Bool
    
    static let `default` = AudioFeedbackSettings(
        preset: .default,
        customSounds: nil,
        volumes: .default,
        isEnabled: true
    )
    
    static let userDefaultsKey = "audioFeedbackSettings"
}
