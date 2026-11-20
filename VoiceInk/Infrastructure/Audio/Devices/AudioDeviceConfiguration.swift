import AVFoundation
import CoreAudio
import Foundation
import os

struct AudioInputChannel: Identifiable, Equatable, Sendable {
    let id: UInt32
    let name: String?
}

/// Audio device configuration queries (does NOT modify system default device)
class AudioDeviceConfiguration {
    private static let logger = Logger(subsystem: AppLogger.subsystem, category: "AudioDeviceConfiguration")

    /// Count all input buffers, matching AUHAL's flattened input-channel numbering.
    static func inputChannels(deviceID: AudioDeviceID) -> [AudioInputChannel] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return [] }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, storage) == noErr else { return [] }
        let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
        let channelCount = buffers.reduce(UInt32(0)) { $0 + $1.mNumberChannels }
        guard channelCount > 0 else { return [] }

        return (1...channelCount).map { channel in
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyElementName,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: channel
            )
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)
            // Core Audio transfers ownership of element-name CFStrings to the caller.
            guard status == noErr, let name else { return AudioInputChannel(id: channel, name: nil) }
            let label = (name.takeRetainedValue() as String).trimmingCharacters(in: .whitespacesAndNewlines)
            return AudioInputChannel(id: channel, name: label.isEmpty ? nil : label)
        }
    }

    /// Gets the current system default input device (for reference only)
    static func getDefaultInputDevice() -> AudioDeviceID? {
        var defaultDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &defaultDeviceID
        )
        if status != noErr {
            logger.error("Failed to get current default input device: \(status, privacy: .public)")
            return nil
        }
        return defaultDeviceID
    }
}
