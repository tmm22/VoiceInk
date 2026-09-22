import Foundation

/// Shared transaction boundary: every reconfiguration failure follows the same recovery path.
enum RecordingDeviceSwitch {
    struct Failure: Error {
        let changeError: Error
        let recoveryError: Error?
        var recordingStopped: Bool { recoveryError != nil }
    }

    static func perform(
        change: () throws -> Void,
        recover: () throws -> Void,
        stop: () -> Void
    ) throws {
        do {
            try change()
        } catch {
            let changeError = error
            do {
                try recover()
            } catch {
                stop()
                throw Failure(changeError: changeError, recoveryError: error)
            }
            throw Failure(changeError: changeError, recoveryError: nil)
        }
    }
}
