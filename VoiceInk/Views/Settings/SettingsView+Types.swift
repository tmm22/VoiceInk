import SwiftUI

// MARK: - Searchable Setting

struct SearchableSetting {
    let tab: SettingsTab
    let section: String
    let keywords: [String]
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case audio = "Audio"
    case transcription = "Transcription"
    case shortcuts = "Shortcuts"
    case enhancement = "Enhancement"
    case data = "Data"
    case permissions = "Permissions"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .general: return "gear"
        case .audio: return "speaker.wave.2.fill"
        case .transcription: return "waveform.circle"
        case .shortcuts: return "command"
        case .enhancement: return "sparkles"
        case .data: return "lock.shield"
        case .permissions: return "hand.raised.fill"
        }
    }
}

// MARK: - Text Extension for Settings Description

extension Text {
    func settingsDescription() -> some View {
        self
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}