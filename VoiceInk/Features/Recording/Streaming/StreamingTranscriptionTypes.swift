import Foundation

/// Lifecycle states for a streaming transcription session.
enum StreamingState {
    case idle
    case connecting
    case streaming
    case committing
    case done
    case failed
    case cancelled
}

enum StreamingStopResult: Equatable {
    case finalized(text: String)
    case requiresBatchFallback
    /// The provider never acknowledged the final commit. `partialText` holds only the segments
    /// committed before the deadline, so the session prefers the complete on-disk recording.
    case timedOut(partialText: String)
}
