import AVFoundation
import Accelerate
import Atomics
import AudioToolbox
import CoreAudio
import Foundation
import os

extension CoreAudioRecorder {
    // MARK: - Device Info Logging

    func logDeviceDetails(deviceID: AudioDeviceID) {
        // Get device name
        let deviceName =
            getDeviceStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceNameCFString) ?? "Unknown"

        // Get device UID
        let deviceUID =
            getDeviceStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) ?? "Unknown"

        // Get transport type
        let transportType = getTransportType(deviceID: deviceID)

        // Get manufacturer
        let manufacturer =
            getDeviceStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceManufacturerCFString)
            ?? "Unknown"

        logger.notice("🎙️ Device info: name=\(deviceName, privacy: .public), uid=\(deviceUID, privacy: .public)")
        logger.notice(
            "🎙️ Device details: transport=\(transportType, privacy: .public), manufacturer=\(manufacturer, privacy: .public)"
        )

        // Get buffer frame size
        if let bufferSize = getBufferFrameSize(deviceID: deviceID) {
            let latencyMs = (Double(bufferSize) / 48000.0) * 1000.0  // Approximate latency assuming 48kHz
            logger.notice(
                "🎙️ Buffer size: \(bufferSize, privacy: .public) frames, ~latency: \(String(format: "%.1f", latencyMs), privacy: .public)ms"
            )
        }
    }

    func getDeviceStringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var property: Unmanaged<CFString>?

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &property
        )

        return status == noErr ? property?.takeUnretainedValue() as String? : nil
    }

    func getTransportType(deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &transportType
        )

        if status != noErr {
            return "Unknown"
        }

        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return "Built-in"
        case kAudioDeviceTransportTypeUSB:
            return "USB"
        case kAudioDeviceTransportTypeBluetooth:
            return "Bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE:
            return "Bluetooth LE"
        case kAudioDeviceTransportTypeAggregate:
            return "Aggregate"
        case kAudioDeviceTransportTypeVirtual:
            return "Virtual"
        case kAudioDeviceTransportTypePCI:
            return "PCI"
        case kAudioDeviceTransportTypeFireWire:
            return "FireWire"
        case kAudioDeviceTransportTypeDisplayPort:
            return "DisplayPort"
        case kAudioDeviceTransportTypeHDMI:
            return "HDMI"
        case kAudioDeviceTransportTypeAVB:
            return "AVB"
        case kAudioDeviceTransportTypeThunderbolt:
            return "Thunderbolt"
        default:
            return "Other (\(transportType))"
        }
    }

    func getBufferFrameSize(deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var bufferSize: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &bufferSize
        )

        return status == noErr ? bufferSize : nil
    }

    func getPreferredInputChannels(deviceID: AudioDeviceID) -> [UInt32]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var channels = [UInt32](repeating: 0, count: 2)
        var propertySize = UInt32(MemoryLayout<UInt32>.size * channels.count)
        let status = channels.withUnsafeMutableBytes { bytes -> OSStatus in
            guard let baseAddress = bytes.baseAddress else { return kAudio_ParamError }
            return AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &propertySize,
                baseAddress
            )
        }

        return status == noErr ? channels : nil
    }

    /// Checks if a device is currently available using Apple's kAudioDevicePropertyDeviceIsAlive
    func isDeviceAvailable(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isAlive: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &isAlive
        )

        return status == noErr && isAlive == 1
    }
}
