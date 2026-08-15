import SwiftUI

// MARK: - Context Panel Destination

enum ContextPanelDestination: String, CaseIterable, Identifiable {
    case queue
    case history
    case snippets
    case glossary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queue:
            return "Queue"
        case .history:
            return "History"
        case .snippets:
            return "Library"
        case .glossary:
            return "Glossary"
        }
    }

    var icon: String {
        switch self {
        case .queue:
            return "list.bullet.rectangle"
        case .history:
            return "clock.arrow.circlepath"
        case .snippets:
            return "text.badge.star"
        case .glossary:
            return "character.bubble"
        }
    }
}

// MARK: - Composer Utility

enum ComposerUtility: String, CaseIterable, Identifiable {
    case transcription
    case urlImport
    case sampleText
    case chunking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcription:
            return "Transcription"
        case .urlImport:
            return "URL Import"
        case .sampleText:
            return "Sample Text"
        case .chunking:
            return "Chunk Helper"
        }
    }

    var icon: String {
        switch self {
        case .transcription:
            return "waveform"
        case .urlImport:
            return "link.badge.plus"
        case .sampleText:
            return "text.quote"
        case .chunking:
            return "square.split.2x2"
        }
    }

    var helpText: String {
        switch self {
        case .transcription:
            return "Transcribe an audio recording and generate a cleaned script"
        case .urlImport:
            return "Pull readable text from a web article"
        case .sampleText:
            return "Fill the editor with ready-made copy"
        case .chunking:
            return "Preview how your batch segments will split"
        }
    }
}