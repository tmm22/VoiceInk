import Combine

@MainActor
final class PartialTranscriptState: ObservableObject {
    @Published var text = ""
}

extension WhisperState {
    var partialTranscript: String {
        get { partialTranscriptState.text }
        set { partialTranscriptState.text = newValue }
    }
}
