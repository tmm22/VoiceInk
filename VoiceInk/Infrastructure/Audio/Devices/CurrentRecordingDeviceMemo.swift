import CoreAudio

/// Shares one current-recording-device resolution between the rows of a single view build.
///
/// Device lists mark the active row by comparing each row against the resolved recording device.
/// Resolving it per row repeats the same Core Audio queries once per device on the main actor.
/// A view creates one memo per build and its rows read `deviceID`:
/// - nothing is resolved unless a row is actually built, so a view whose rows are never realised
///   does no more work than it did when every row resolved for itself;
/// - rows built in the same synchronous pass share one resolution;
/// - the value is dropped once that pass has returned to the main run loop, so rows built later
///   from the same memo resolve again and are never staler than a per-row resolution would be.
@MainActor
final class CurrentRecordingDeviceMemo {
    private let resolve: () -> AudioDeviceID
    private var cachedDeviceID: AudioDeviceID?

    init(resolve: @escaping () -> AudioDeviceID) {
        self.resolve = resolve
    }

    convenience init(deviceManager: AudioDeviceManager) {
        self.init(resolve: { deviceManager.getCurrentDevice() })
    }

    var deviceID: AudioDeviceID {
        if let cachedDeviceID {
            return cachedDeviceID
        }

        let resolvedDeviceID = resolve()
        cachedDeviceID = resolvedDeviceID
        // Runs after the current synchronous view update, never in the middle of it.
        Task { @MainActor [weak self] in
            self?.cachedDeviceID = nil
        }
        return resolvedDeviceID
    }
}
