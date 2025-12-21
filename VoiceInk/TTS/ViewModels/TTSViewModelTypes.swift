import Foundation
import UniformTypeIdentifiers

// MARK: - Snippet Insert Mode

/// Determines how text snippets are inserted into the editor
enum SnippetInsertMode {
    case replace
    case append
}

// MARK: - Transcript Format

/// Supported transcript export formats
enum TranscriptFormat {
    case srt
    case vtt

    var fileExtension: String {
        switch self {
        case .srt:
            return "srt"
        case .vtt:
            return "vtt"
        }
    }

    var contentType: UTType? {
        UTType(filenameExtension: fileExtension)
    }
}

// MARK: - Generation Output

/// Represents the output of a TTS generation operation
struct GenerationOutput {
    let audioData: Data
    let transcript: TranscriptBundle?
    let duration: TimeInterval
}

// MARK: - Transcription Stage

/// Represents the current stage of the transcription process
enum TranscriptionStage: Equatable {
    case idle
    case recording
    case transcribing
    case summarising
    case cleaning
    case complete
    case error
}

// MARK: - TTS Provider Type

/// Available TTS provider options
enum TTSProviderType: String, CaseIterable {
    case elevenLabs = "ElevenLabs"
    case openAI = "OpenAI"
    case google = "Google"
    case tightAss = "Tight Ass Mode"
    
    var displayName: String {
        return self.rawValue
    }
    
    var icon: String {
        switch self {
        case .elevenLabs:
            return "waveform"
        case .openAI:
            return "cpu"
        case .google:
            return "cloud"
        case .tightAss:
            return "internaldrive"
        }
    }
}
