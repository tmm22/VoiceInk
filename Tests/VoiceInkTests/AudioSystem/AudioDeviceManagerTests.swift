import CoreAudio
import XCTest
@testable import VoiceInk

/// Tests the deterministic parts of audio-device selection and recording routing.
/// Hardware enumeration itself is intentionally treated as an integration boundary.
@available(macOS 14.0, *)
@MainActor
final class AudioDeviceManagerTests: XCTestCase {
    private var deviceManager: AudioDeviceManager!

    override func setUp() async throws {
        try await super.setUp()
        deviceManager = AudioDeviceManager()
        try await Task.sleep(for: .milliseconds(100))
    }

    override func tearDown() async throws {
        deviceManager.recordingDidStop()
        deviceManager = nil
        UserDefaults.standard.removeObject(forKey: "selectedAudioDeviceUID")
        try await super.tearDown()
    }

    func testAvailableDevicesHaveValidMetadata() {
        for device in deviceManager.availableDevices {
            XCTAssertNotEqual(device.id, 0)
            XCTAssertFalse(device.uid.isEmpty)
            XCTAssertFalse(device.name.isEmpty)
        }
    }

    func testLoadAvailableDevicesCompletes() async {
        let loaded = expectation(description: "Devices loaded")
        deviceManager.loadAvailableDevices { loaded.fulfill() }
        await fulfillment(of: [loaded], timeout: 5)
    }

    func testRecordingSessionLifecycleIsEncapsulated() {
        XCTAssertFalse(deviceManager.isRecordingActive)
        XCTAssertNil(deviceManager.activeRecordingDeviceID)

        deviceManager.beginRecordingSetup(deviceID: 42)
        XCTAssertTrue(deviceManager.isRecordingActive)
        XCTAssertEqual(deviceManager.activeRecordingDeviceID, 42)

        deviceManager.recordingDidStart(deviceID: 43)
        XCTAssertTrue(deviceManager.isRecordingActive)
        XCTAssertEqual(deviceManager.activeRecordingDeviceID, 43)

        deviceManager.recordingDidStop()
        XCTAssertFalse(deviceManager.isRecordingActive)
        XCTAssertNil(deviceManager.activeRecordingDeviceID)
    }

    func testRecordingDeviceChangeRequestIsDeduplicated() {
        deviceManager.beginRecordingSetup(deviceID: 42)
        deviceManager.requestRecordingDeviceChange(reason: .deviceUnavailable)
        XCTAssertTrue(deviceManager.recordingDeviceSession.isDeviceChangePending)

        deviceManager.requestRecordingDeviceChange(reason: .closedLid)
        XCTAssertTrue(deviceManager.recordingDeviceSession.isDeviceChangePending)

        deviceManager.recordingDeviceChangeFinished(activeDeviceID: 43)
        XCTAssertFalse(deviceManager.recordingDeviceSession.isDeviceChangePending)
        XCTAssertEqual(deviceManager.activeRecordingDeviceID, 43)
    }

    func testInvalidSelectedDeviceFallsBackGracefully() {
        deviceManager.selectedDeviceID = AudioDeviceID.max
        let resolved = deviceManager.getCurrentDevice()
        if deviceManager.availableDevices.isEmpty {
            XCTAssertEqual(resolved, 0)
        } else {
            XCTAssertNotEqual(resolved, AudioDeviceID.max)
        }
    }

    func testPrioritizedDeviceSelectionUsesAvailableDevice() throws {
        guard let firstDevice = deviceManager.availableDevices.first else {
            throw XCTSkip("No input devices are available")
        }

        deviceManager.selectInputMode(.prioritized)
        deviceManager.updatePriorities(
            devices: [PrioritizedDevice(id: firstDevice.uid, name: firstDevice.name, priority: 1)]
        )

        XCTAssertEqual(deviceManager.selectedDeviceID, firstDevice.id)
    }

    func testDeviceNameMatchesEnumeratedMetadata() throws {
        guard let firstDevice = deviceManager.availableDevices.first else {
            throw XCTSkip("No input devices are available")
        }
        XCTAssertEqual(deviceManager.getDeviceName(deviceID: firstDevice.id), firstDevice.name)
    }

    func testManagerDeallocatesAfterUse() async {
        weak var weakManager: AudioDeviceManager?
        do {
            let manager = AudioDeviceManager()
            weakManager = manager
            _ = manager.getCurrentDevice()
            manager.beginRecordingSetup(deviceID: 42)
            manager.recordingDidStop()
        }

        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(weakManager)
    }
}
