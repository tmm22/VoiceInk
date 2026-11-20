import Foundation

struct AudioInputChannelSelection: Equatable, Sendable {
    let deviceChannelIndices: [Int32]

    /// Saved and Core Audio preferred channel numbers are one-based; AUHAL maps are zero-based.
    static func resolve(
        deviceChannelCount: UInt32,
        preferredStereoChannels: [UInt32]?,
        selectedChannels: [UInt32]? = nil
    ) -> AudioInputChannelSelection {
        guard deviceChannelCount > 0 else {
            return AudioInputChannelSelection(deviceChannelIndices: [])
        }

        if let selectedChannels = validatedChannels(selectedChannels, deviceChannelCount: deviceChannelCount) {
            return AudioInputChannelSelection(deviceChannelIndices: selectedChannels.map { Int32($0 - 1) })
        }

        // Preserve the existing automatic policy, including preferred-channel ordering.
        let fallback = (0..<min(deviceChannelCount, 2)).map(Int32.init)
        guard let preferredStereoChannels,
              !preferredStereoChannels.isEmpty,
              preferredStereoChannels.allSatisfy({ $0 > 0 && $0 <= deviceChannelCount && $0 - 1 <= UInt32(Int32.max) }) else {
            return AudioInputChannelSelection(deviceChannelIndices: fallback)
        }

        var seen = Set<UInt32>()
        let preferred = preferredStereoChannels.compactMap { channel -> Int32? in
            guard seen.insert(channel).inserted else { return nil }
            return Int32(channel - 1)
        }
        return AudioInputChannelSelection(deviceChannelIndices: preferred)
    }

    /// Manual overrides select one input; Automatic may still use a preferred pair.
    static func validatedChannels(_ channels: [UInt32]?, deviceChannelCount: UInt32) -> [UInt32]? {
        guard let channels, channels.count == 1, deviceChannelCount > 0,
              channels.allSatisfy({ $0 > 0 && $0 <= deviceChannelCount && $0 - 1 <= UInt32(Int32.max) }) else {
            return nil
        }
        return channels
    }
}
