import Atomics
import Foundation

/// One atomic word couples callback admission to resource ownership. Lifecycle mutations must
/// close admission, stop the hardware, and drain admitted callbacks before touching their buffers.
final class AudioCallbackGate: @unchecked Sendable {
    private static let closedBit: UInt64 = 1 << 63
    private let state = ManagedAtomic<UInt64>(closedBit)

    func tryEnter() -> Bool {
        var observed = state.load(ordering: .acquiring)
        while observed & Self.closedBit == 0 {
            let result = state.compareExchange(
                expected: observed, desired: observed + 1, ordering: .acquiringAndReleasing
            )
            if result.exchanged { return true }
            observed = result.original
        }
        return false
    }

    func leave() {
        state.wrappingDecrement(ordering: .releasing)
    }

    func close() {
        _ = state.loadThenBitwiseOr(with: Self.closedBit, ordering: .acquiringAndReleasing)
    }

    /// Only the serial hardware owner may reopen, after all callbacks have drained.
    func open() {
        let result = state.compareExchange(
            expected: Self.closedBit, desired: 0, ordering: .acquiringAndReleasing
        )
        precondition(result.exchanged, "Cannot reopen audio capture while callbacks are active")
    }

    var isDrained: Bool {
        state.load(ordering: .acquiring) == Self.closedBit
    }

    /// Run off the main/render threads. The deadline emits a diagnostic; it is not a lifetime
    /// barrier. Resources remain owned until even a stalled callback has actually returned.
    func waitUntilDrained(
        stalledAfter: TimeInterval = 5,
        onStalledDrain: () -> Void = {},
        onSlowDrain: () -> Void
    ) {
        let started = DispatchTime.now().uptimeNanoseconds
        let warningTime = started + 200_000_000
        let stalledTime = started + UInt64(max(0, stalledAfter) * 1_000_000_000)
        var warned = false
        var reportedStall = false
        while !isDrained {
            let now = DispatchTime.now().uptimeNanoseconds
            if !warned, now >= warningTime {
                warned = true
                onSlowDrain()
            }
            if !reportedStall, now >= stalledTime {
                reportedStall = true
                onStalledDrain()
            }
            // A stuck driver must not turn the hardware owner into a permanent 10kHz poller.
            usleep(warned ? 10_000 : 100)
        }
    }
}
