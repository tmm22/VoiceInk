import Foundation
import CoreAudio
import os

enum AudioDeviceHardware {
    static func deviceName(deviceID: AudioDeviceID, logger: Logger) -> String? {
        let name: CFString? = property(
            deviceID: deviceID,
            selector: kAudioDevicePropertyDeviceNameCFString,
            logger: logger
        )
        return name as String?
    }

    static func deviceUID(deviceID: AudioDeviceID, logger: Logger) -> String? {
        let uid: CFString? = property(
            deviceID: deviceID,
            selector: kAudioDevicePropertyDeviceUID,
            logger: logger
        )
        return uid as String?
    }

    static func isValidInputDevice(deviceID: AudioDeviceID, logger: Logger) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &propertySize
        )

        if result != noErr {
            logger.error("Error checking input capability for device \(deviceID): \(result)")
            return false
        }

        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(propertySize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPointer.deallocate() }
        let bufferList = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)

        result = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            bufferList
        )

        if result != noErr {
            logger.error("Error getting stream configuration for device \(deviceID): \(result)")
            return false
        }

        let bufferCount = Int(bufferList.pointee.mNumberBuffers)
        return bufferCount > 0
    }

    private static func property<T>(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        logger: Logger
    ) -> T? {
        guard deviceID != 0 else { return nil }

        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize = UInt32(MemoryLayout<T>.size)
        let propertyPointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { propertyPointer.deallocate() }

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            propertyPointer
        )

        if status != noErr {
            logger.error("Failed to get device property \(selector) for device \(deviceID): \(status)")
            return nil
        }

        return propertyPointer.pointee
    }
}
