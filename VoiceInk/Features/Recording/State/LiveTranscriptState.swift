import Combine
import Foundation

/// Holds the in-progress streaming transcript for the recorder UI.
///
/// Streaming providers emit partials several times a second. Keeping the text in its own
/// observable object means only the live-transcript leaf views re-render on each partial; the
/// engine's other observers (menu bar, history player, file import) are not invalidated.
@MainActor
final class LiveTranscriptState: ObservableObject {
    @Published private(set) var text: String = ""

    var isEmpty: Bool { text.isEmpty }

    func update(_ text: String) {
        guard text != self.text else { return }
        self.text = text
    }

    func clear() {
        update("")
    }
}
