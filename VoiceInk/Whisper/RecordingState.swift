import Foundation

// MARK: - Recording State Machine
enum RecordingState: Equatable, CustomStringConvertible {
    case idle
    case recording
    case transcribing
    case enhancing
    case busy

    var description: String {
        switch self {
        case .idle: return "idle"
        case .recording: return "recording"
        case .transcribing: return "transcribing"
        case .enhancing: return "enhancing"
        case .busy: return "busy"
        }
    }
}