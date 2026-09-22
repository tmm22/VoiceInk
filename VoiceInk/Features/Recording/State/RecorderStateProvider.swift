import Foundation

// Protocol for objects that provide live recorder state to the UI.
@MainActor
protocol RecorderStateProvider: AnyObject {
    var recordingState: RecordingState { get }
    /// Flips only when the live transcript goes from empty to non-empty or back, so layout can
    /// react without observing every partial update.
    var hasPartialTranscript: Bool { get }
    /// Streaming partial text. Observe this object directly in the leaf view that renders it.
    var liveTranscript: LiveTranscriptState { get }
}
