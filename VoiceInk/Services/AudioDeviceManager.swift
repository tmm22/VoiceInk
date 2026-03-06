import Foundation
import CoreAudio
import AVFoundation
import os

@MainActor
class AudioDeviceManager: ObservableObject {
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "AudioDeviceManager")
    @Published var availableDevices: [(id: AudioDeviceID, uid: String, name: String)] = []
    @Published var selectedDeviceID: AudioDeviceID?
    @Published var inputMode: AudioInputMode = .custom
    @Published var prioritizedDevices: [PrioritizedDevice] = []

    var isRecordingActive = false

    static let shared = AudioDeviceManager()

    init() {
        loadPrioritizedDevices()
        loadAvailableDevices { [weak self] in
            self?.initializeSelectedDevice()
        }

        if let savedMode = AppSettings.AudioInput.audioInputModeRawValue,
           let mode = AudioInputMode(rawValue: savedMode) {
            inputMode = mode
        } else {
            inputMode = .systemDefault
        }

        loadAvailableDevices { [weak self] in
            self?.initializeSelectedDevice()
        }

        setupDeviceChangeNotifications()
    }

    func getSystemDefaultDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
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
            &deviceID
        )

        guard status == noErr, deviceID != 0 else {
            logger.error("Failed to get system default device: \(status)")
            return nil
        }
        return deviceID
    }

    func getSystemDefaultDeviceName() -> String? {
        guard let deviceID = getSystemDefaultDevice() else { return nil }
        return AudioDeviceHardware.deviceName(deviceID: deviceID, logger: logger)
    }

    func getDeviceName(deviceID: AudioDeviceID) -> String? {
        AudioDeviceHardware.deviceName(deviceID: deviceID, logger: logger)
    }

    func loadAvailableDevices(completion: (() -> Void)? = nil) {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var result = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        )

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )

        if result != noErr {
            logger.error("Error getting audio devices: \(result)")
            return
        }

        let devices = deviceIDs.compactMap { deviceID -> (id: AudioDeviceID, uid: String, name: String)? in
            guard let name = AudioDeviceHardware.deviceName(deviceID: deviceID, logger: logger),
                  let uid = AudioDeviceHardware.deviceUID(deviceID: deviceID, logger: logger),
                  AudioDeviceHardware.isValidInputDevice(deviceID: deviceID, logger: logger) else {
                return nil
            }
            return (id: deviceID, uid: uid, name: name)
        }

        logger.info("Found \(devices.count) input devices")
        devices.forEach { device in
            logger.info("Available device: \(device.name) (ID: \(device.id))")
        }

        availableDevices = devices.map { ($0.id, $0.uid, $0.name) }
        if let currentID = selectedDeviceID, !devices.contains(where: { $0.id == currentID }) {
            logger.warning("Currently selected device is no longer available")
            fallbackToDefaultDevice()
        }
        completion?()
    }

    func selectDevice(id: AudioDeviceID) {
        if let deviceToSelect = availableDevices.first(where: { $0.id == id }) {
            let uid = deviceToSelect.uid
            selectedDeviceID = id
            AppSettings.AudioInput.selectedAudioDeviceUID = uid
            logger.info("Device selection saved with UID: \(uid)")
            notifyDeviceChange()
        } else {
            logger.error("Attempted to select unavailable device: \(id)")
            fallbackToDefaultDevice()
        }
    }

    func selectDeviceAndSwitchToCustomMode(id: AudioDeviceID) {
        if let deviceToSelect = availableDevices.first(where: { $0.id == id }) {
            let uid = deviceToSelect.uid
            inputMode = .custom
            selectedDeviceID = id
            AppSettings.AudioInput.audioInputModeRawValue = AudioInputMode.custom.rawValue
            AppSettings.AudioInput.selectedAudioDeviceUID = uid
            notifyDeviceChange()
        } else {
            logger.error("Attempted to select unavailable device: \(id)")
            fallbackToDefaultDevice()
        }
    }

    func selectInputMode(_ mode: AudioInputMode) {
        inputMode = mode
        AppSettings.AudioInput.audioInputModeRawValue = mode.rawValue

        if mode == .systemDefault {
            selectedDeviceID = nil
            AppSettings.AudioInput.selectedAudioDeviceUID = nil
        } else if mode == .custom, selectedDeviceID == nil {
            if let firstDevice = availableDevices.first {
                selectDevice(id: firstDevice.id)
            }
        } else if mode == .prioritized, selectedDeviceID == nil {
            selectHighestPriorityAvailableDevice()
        }

        notifyDeviceChange()
    }

    func getCurrentDevice() -> AudioDeviceID {
        switch inputMode {
        case .systemDefault:
            return getSystemDefaultDevice() ?? findBestAvailableDevice() ?? 0
        case .custom:
            if let id = selectedDeviceID, isDeviceAvailable(id) {
                return id
            }
            return findBestAvailableDevice() ?? 0
        case .prioritized:
            let sortedDevices = prioritizedDevices.sorted { $0.priority < $1.priority }
            for device in sortedDevices {
                if let available = availableDevices.first(where: { $0.uid == device.id }) {
                    return available.id
                }
            }
            return findBestAvailableDevice() ?? 0
        }
    }

    func savePrioritizedDevices() {
        if let data = try? JSONEncoder().encode(prioritizedDevices) {
            AppSettings.AudioInput.prioritizedDevicesData = data
            logger.info("Saved \(self.prioritizedDevices.count) prioritized devices")
        }
    }

    func addPrioritizedDevice(uid: String, name: String) {
        guard !prioritizedDevices.contains(where: { $0.id == uid }) else { return }
        let nextPriority = (prioritizedDevices.map { $0.priority }.max() ?? -1) + 1
        prioritizedDevices.append(PrioritizedDevice(id: uid, name: name, priority: nextPriority))
        savePrioritizedDevices()
    }

    func removePrioritizedDevice(id: String) {
        let wasSelected = selectedDeviceID == availableDevices.first(where: { $0.uid == id })?.id
        prioritizedDevices.removeAll { $0.id == id }

        prioritizedDevices = prioritizedDevices.enumerated().map { index, device in
            PrioritizedDevice(id: device.id, name: device.name, priority: index)
        }
        savePrioritizedDevices()

        if wasSelected && inputMode == .prioritized {
            selectHighestPriorityAvailableDevice()
        }
    }

    func updatePriorities(devices: [PrioritizedDevice]) {
        prioritizedDevices = devices
        savePrioritizedDevices()

        if inputMode == .prioritized {
            selectHighestPriorityAvailableDevice()
        }

        notifyDeviceChange()
    }

    deinit {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            audioDevicePropertyListener,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        if status != noErr {
            os_log("AudioDeviceManager: Failed to remove property listener in deinit: %{public}d", type: .error, status)
        }
    }

    private func initializeSelectedDevice() {
        switch inputMode {
        case .systemDefault:
            logger.notice("🎙️ Using System Default mode")
        case .custom:
            logger.notice("🎙️ Using Custom Device mode")
        case .prioritized:
            selectHighestPriorityAvailableDevice()
            return
        }

        if let savedUID = AppSettings.AudioInput.selectedAudioDeviceUID {
            if let device = availableDevices.first(where: { $0.uid == savedUID }) {
                selectedDeviceID = device.id
                logger.info("Loaded saved device UID: \(savedUID), mapped to ID: \(device.id)")
                if let name = AudioDeviceHardware.deviceName(deviceID: device.id, logger: logger) {
                    logger.info("Using saved device: \(name)")
                }
            } else {
                logger.warning("Saved device UID \(savedUID) is no longer available")
                AppSettings.AudioInput.selectedAudioDeviceUID = nil
                fallbackToDefaultDevice()
            }
        }
    }

    private func isDeviceAvailable(_ deviceID: AudioDeviceID) -> Bool {
        availableDevices.contains { $0.id == deviceID }
    }

    private func fallbackToDefaultDevice() {
        logger.notice("🎙️ Current device unavailable, selecting new device...")

        guard let newDeviceID = findBestAvailableDevice() else {
            logger.error("No input devices available!")
            selectedDeviceID = nil
            notifyDeviceChange()
            return
        }

        let newDeviceName = AudioDeviceHardware.deviceName(deviceID: newDeviceID, logger: logger) ?? "Unknown Device"
        logger.notice("🎙️ Auto-selecting new device: \(newDeviceName)")
        selectDevice(id: newDeviceID)
    }

    func findBestAvailableDevice() -> AudioDeviceID? {
        if let device = availableDevices.first(where: { isBuiltInDevice($0.id) }) {
            return device.id
        }
        if let device = availableDevices.first {
            logger.warning("🎙️ No built-in device found, using: \(device.name)")
            return device.id
        }
        return nil
    }

    private func isBuiltInDevice(_ deviceID: AudioDeviceID) -> Bool {
        guard let uid = AudioDeviceHardware.deviceUID(deviceID: deviceID, logger: logger) else {
            return false
        }
        return uid.contains("BuiltIn")
    }

    private func loadPrioritizedDevices() {
        if let data = AppSettings.AudioInput.prioritizedDevicesData,
           let devices = try? JSONDecoder().decode([PrioritizedDevice].self, from: data) {
            prioritizedDevices = devices
        }
    }

    private func selectHighestPriorityAvailableDevice() {
        let sortedDevices = prioritizedDevices.sorted { $0.priority < $1.priority }

        for device in sortedDevices {
            if let availableDevice = availableDevices.first(where: { $0.uid == device.id }) {
                selectedDeviceID = availableDevice.id
                logger.notice("🎙️ Selected prioritized device: \(device.name)")
                notifyDeviceChange()
                return
            }
        }

        fallbackToDefaultDevice()
    }

    private func setupDeviceChangeNotifications() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            audioDevicePropertyListener,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        if status != noErr {
            logger.error("Failed to add device change listener: \(status)")
        }
    }

    func handleDeviceListChange() {
        logger.info("Device list change detected")
        loadAvailableDevices { [weak self] in
            guard let self else { return }

            if inputMode == .systemDefault {
                notifyDeviceChange()
                return
            }

            if isRecordingActive {
                guard let currentID = selectedDeviceID else { return }

                if !isDeviceAvailable(currentID) {
                    logger.warning("🎙️ Recording device \(currentID) no longer available - requesting switch")

                    let newDeviceID: AudioDeviceID?
                    if inputMode == .prioritized {
                        let sortedDevices = prioritizedDevices.sorted { $0.priority < $1.priority }
                        let priorityDeviceID = sortedDevices.compactMap { device in
                            self.availableDevices.first(where: { $0.uid == device.id })?.id
                        }.first

                        if let deviceID = priorityDeviceID {
                            newDeviceID = deviceID
                        } else {
                            logger.warning("🎙️ No priority devices available, using fallback")
                            newDeviceID = findBestAvailableDevice()
                        }
                    } else {
                        newDeviceID = findBestAvailableDevice()
                    }

                    if let deviceID = newDeviceID {
                        selectedDeviceID = deviceID
                        NotificationCenter.default.post(
                            name: .audioDeviceSwitchRequired,
                            object: nil,
                            userInfo: ["newDeviceID": deviceID]
                        )
                    } else {
                        logger.error("No audio input devices available!")
                        NotificationCenter.default.post(name: .toggleMiniRecorder, object: nil)
                    }
                }
                return
            }

            if inputMode == .prioritized {
                selectHighestPriorityAvailableDevice()
            } else if inputMode == .custom,
                      let currentID = selectedDeviceID,
                      !isDeviceAvailable(currentID) {
                fallbackToDefaultDevice()
            }
        }
    }

    private func notifyDeviceChange() {
        NotificationCenter.default.post(name: .audioDeviceChanged, object: nil)
    }
}
