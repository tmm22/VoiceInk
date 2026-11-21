import CoreAudio

/// Candidate ordering for recording-device resolution.
///
/// Kept free of Core Audio queries so the ordering rules can be unit tested: the caller supplies
/// the device classification and usability checks, each of which costs HAL round trips in production.
enum RecordingDeviceCandidateResolver {
    /// Returns the first usable device among `preferredCandidates` followed by `fallbackCandidates()`.
    ///
    /// `excludedDeviceID` is never returned, and a device that appears more than once is only
    /// considered at its first position. The fallback list is built only when no preferred
    /// candidate is usable, which is the same device the eager "preferred + fallback" scan picks:
    /// every preferred candidate has already been rejected by the time the fallback list is read.
    static func firstUsableDevice(
        preferredCandidates: [AudioDeviceID],
        excluding excludedDeviceID: AudioDeviceID?,
        isUsable: (AudioDeviceID) -> Bool,
        fallbackCandidates: () -> [AudioDeviceID]
    ) -> AudioDeviceID? {
        var seen = Set<AudioDeviceID>()

        func firstUsable(in candidates: [AudioDeviceID]) -> AudioDeviceID? {
            candidates.first { deviceID in
                guard deviceID != excludedDeviceID, seen.insert(deviceID).inserted else { return false }
                return isUsable(deviceID)
            }
        }

        return firstUsable(in: preferredCandidates) ?? firstUsable(in: fallbackCandidates())
    }

    /// Orders fallback inputs: internal microphones first, or last while the lid is closed.
    ///
    /// Each device is classified exactly once and keeps its relative position within its group.
    static func fallbackOrder(
        deviceIDs: [AudioDeviceID],
        isClamshellClosed: Bool,
        isInternalMicrophone: (AudioDeviceID) -> Bool
    ) -> [AudioDeviceID] {
        var internalMicrophones: [AudioDeviceID] = []
        var otherInputs: [AudioDeviceID] = []
        for deviceID in deviceIDs {
            if isInternalMicrophone(deviceID) {
                internalMicrophones.append(deviceID)
            } else {
                otherInputs.append(deviceID)
            }
        }
        return isClamshellClosed ? otherInputs + internalMicrophones : internalMicrophones + otherInputs
    }
}
