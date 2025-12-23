import Foundation

struct OnboardingPermission: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let type: PermissionType

    enum PermissionType {
        case microphone
        case audioDeviceSelection
        case accessibility
        case screenRecording
        case keyboardShortcut

        var systemName: String {
            switch self {
            case .microphone: return "mic"
            case .audioDeviceSelection: return "headphones"
            case .accessibility: return "accessibility"
            case .screenRecording: return "rectangle.inset.filled.and.person.filled"
            case .keyboardShortcut: return "keyboard"
            }
        }
    }
}
