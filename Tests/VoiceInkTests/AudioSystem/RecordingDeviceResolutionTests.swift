import CoreAudio
import XCTest
@testable import VoiceInk

/// Pins recording-device candidate ordering against the eager "preferred + fallback" scan it
/// replaced. Everything here runs on plain values; no Core Audio object is queried.
final class RecordingDeviceResolutionTests: XCTestCase {
    // MARK: - Reference implementations (the code the resolver replaced)

    private func eagerScan(
        preferred: [AudioDeviceID],
        fallback: [AudioDeviceID],
        excluding excludedDeviceID: AudioDeviceID?,
        usable: Set<AudioDeviceID>
    ) -> AudioDeviceID? {
        var seen = Set<AudioDeviceID>()
        let candidates = (preferred + fallback).filter { deviceID in
            guard deviceID != excludedDeviceID else { return false }
            return seen.insert(deviceID).inserted
        }
        return candidates.first(where: usable.contains)
    }

    private func twoPassFallbackOrder(
        deviceIDs: [AudioDeviceID],
        internalMicrophones: Set<AudioDeviceID>,
        isClamshellClosed: Bool
    ) -> [AudioDeviceID] {
        let internalInputs = deviceIDs.filter { internalMicrophones.contains($0) }
        let otherInputs = deviceIDs.filter { !internalMicrophones.contains($0) }
        return isClamshellClosed ? otherInputs + internalInputs : internalInputs + otherInputs
    }

    // MARK: - Input generators

    /// Every sequence up to `maxLength`, repeats included (a preferred list can name a device twice).
    private func sequences(of ids: [AudioDeviceID], maxLength: Int) -> [[AudioDeviceID]] {
        var result: [[AudioDeviceID]] = [[]]
        var frontier: [[AudioDeviceID]] = [[]]
        for _ in 0..<maxLength {
            frontier = frontier.flatMap { prefix in ids.map { prefix + [$0] } }
            result += frontier
        }
        return result
    }

    /// Every ordering of every subset (the fallback list never repeats a device).
    private func orderedSubsets(of ids: [AudioDeviceID]) -> [[AudioDeviceID]] {
        var result: [[AudioDeviceID]] = [[]]
        var frontier: [[AudioDeviceID]] = [[]]
        for _ in ids {
            frontier = frontier.flatMap { prefix in
                ids.filter { !prefix.contains($0) }.map { prefix + [$0] }
            }
            result += frontier
        }
        return result
    }

    private func subsets(of ids: [AudioDeviceID]) -> [Set<AudioDeviceID>] {
        (0..<(1 << ids.count)).map { mask in
            Set(ids.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
        }
    }

    // MARK: - firstUsableDevice

    func testResolvedDeviceMatchesEagerScanForEveryCombination() {
        let preferredLists = sequences(of: [1, 2, 3], maxLength: 2) + [[1, 1, 2], [2, 1, 2], [3, 3, 3], [1, 2, 3], [3, 2, 1]]
        let fallbackLists = orderedSubsets(of: [1, 2, 3, 4])
        let exclusions: [AudioDeviceID?] = [nil, 1, 2, 3, 4]
        let usableSets = subsets(of: [1, 2, 3, 4])

        var combinations = 0
        var failures: [String] = []

        for preferred in preferredLists {
            for fallback in fallbackLists {
                for excluded in exclusions {
                    for usable in usableSets {
                        combinations += 1
                        var checksPerDevice: [AudioDeviceID: Int] = [:]
                        var fallbackBuilds = 0

                        let resolved = RecordingDeviceCandidateResolver.firstUsableDevice(
                            preferredCandidates: preferred,
                            excluding: excluded,
                            isUsable: { deviceID in
                                checksPerDevice[deviceID, default: 0] += 1
                                return usable.contains(deviceID)
                            },
                            fallbackCandidates: {
                                fallbackBuilds += 1
                                return fallback
                            }
                        )

                        let expected = eagerScan(
                            preferred: preferred, fallback: fallback, excluding: excluded, usable: usable
                        )
                        let preferredHasUsableDevice = preferred.contains { $0 != excluded && usable.contains($0) }
                        let excludedWasChecked = excluded.map { checksPerDevice[$0] != nil } ?? false

                        let isCorrect = resolved == expected
                            && fallbackBuilds == (preferredHasUsableDevice ? 0 : 1)
                            && !checksPerDevice.values.contains { $0 > 1 }
                            && !excludedWasChecked
                        if !isCorrect, failures.count < 5 {
                            failures.append(
                                "preferred=\(preferred) fallback=\(fallback) excluded=\(String(describing: excluded)) "
                                    + "usable=\(usable.sorted()) resolved=\(String(describing: resolved)) "
                                    + "expected=\(String(describing: expected)) fallbackBuilds=\(fallbackBuilds)"
                            )
                        }
                    }
                }
            }
        }

        XCTAssertGreaterThan(combinations, 90_000)
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testUsablePreferredDeviceWinsWithoutBuildingFallbackList() {
        let resolved = RecordingDeviceCandidateResolver.firstUsableDevice(
            preferredCandidates: [7, 8],
            excluding: nil,
            isUsable: { $0 == 8 },
            fallbackCandidates: {
                XCTFail("The fallback list must not be built when a preferred device is usable")
                return [9]
            }
        )

        XCTAssertEqual(resolved, 8)
    }

    func testExcludedPreferredDeviceFallsThroughToFallbackOrder() {
        let resolved = RecordingDeviceCandidateResolver.firstUsableDevice(
            preferredCandidates: [7],
            excluding: 7,
            isUsable: { _ in true },
            fallbackCandidates: { [7, 9, 8] }
        )

        XCTAssertEqual(resolved, 9)
    }

    func testNoUsableCandidateResolvesToNil() {
        let resolved = RecordingDeviceCandidateResolver.firstUsableDevice(
            preferredCandidates: [7],
            excluding: nil,
            isUsable: { _ in false },
            fallbackCandidates: { [7, 8] }
        )

        XCTAssertNil(resolved)
    }

    // MARK: - fallbackOrder

    func testFallbackOrderMatchesTwoPassFilterForEveryClassification() {
        let deviceLists: [[AudioDeviceID]] = [[], [1], [1, 2], [2, 1], [1, 2, 3], [3, 1, 2, 4], [4, 3, 2, 1]]

        for deviceIDs in deviceLists {
            for internalMicrophones in subsets(of: deviceIDs) {
                for isClamshellClosed in [false, true] {
                    var classifications: [AudioDeviceID: Int] = [:]
                    let order = RecordingDeviceCandidateResolver.fallbackOrder(
                        deviceIDs: deviceIDs,
                        isClamshellClosed: isClamshellClosed,
                        isInternalMicrophone: { deviceID in
                            classifications[deviceID, default: 0] += 1
                            return internalMicrophones.contains(deviceID)
                        }
                    )

                    XCTAssertEqual(
                        order,
                        twoPassFallbackOrder(
                            deviceIDs: deviceIDs,
                            internalMicrophones: internalMicrophones,
                            isClamshellClosed: isClamshellClosed
                        ),
                        "devices=\(deviceIDs) internal=\(internalMicrophones.sorted()) closed=\(isClamshellClosed)"
                    )
                    XCTAssertEqual(classifications.count, deviceIDs.count)
                    XCTAssertFalse(classifications.values.contains { $0 != 1 }, "Each device is classified once")
                }
            }
        }
    }

    func testInternalMicrophonesMoveBehindOtherInputsWhileLidIsClosed() {
        let isInternalMicrophone: (AudioDeviceID) -> Bool = { $0 == 1 || $0 == 3 }

        XCTAssertEqual(
            RecordingDeviceCandidateResolver.fallbackOrder(
                deviceIDs: [1, 2, 3, 4], isClamshellClosed: false, isInternalMicrophone: isInternalMicrophone
            ),
            [1, 3, 2, 4]
        )
        XCTAssertEqual(
            RecordingDeviceCandidateResolver.fallbackOrder(
                deviceIDs: [1, 2, 3, 4], isClamshellClosed: true, isInternalMicrophone: isInternalMicrophone
            ),
            [2, 4, 1, 3]
        )
    }
}

/// The manager's saved-channel lookup, limited to what needs neither Core Audio nor the app's stored
/// device selection. Candidate ordering is covered by the pure resolver tests above; the hosted test
/// process shares the installed app's preferences, so these tests never write to them.
@MainActor
final class RecordingDeviceResolutionManagerTests: XCTestCase {
    // Far outside the range of object IDs the HAL hands out, so these never name a real device.
    private let deviceA: AudioDeviceID = 4_000_000_001
    private let deviceB: AudioDeviceID = 4_000_000_002

    func testInputChannelsAreNilWithoutSavedSelection() {
        let manager = AudioDeviceManager()
        manager.availableDevices = [
            (id: deviceA, uid: "voiceink-tests-device-a", name: "Test Input A"),
            (id: deviceB, uid: "voiceink-tests-device-b", name: "Test Input B"),
        ]

        XCTAssertNil(manager.selectedInputChannels(for: deviceA))
        XCTAssertNil(manager.selectedInputChannels(for: 4_000_000_009), "Unknown devices have no selection")
    }
}

@MainActor
final class RecordingDeviceResolutionMemoTests: XCTestCase {
    /// Lets main-actor work queued so far (including the memo's own reset) run before continuing.
    private func returnToRunLoop() async {
        for _ in 0..<3 {
            await Task { @MainActor in }.value
            await Task.yield()
        }
    }

    func testNothingIsResolvedUntilARowAsks() {
        var resolutions = 0
        let memo = CurrentRecordingDeviceMemo {
            resolutions += 1
            return 42
        }

        XCTAssertEqual(resolutions, 0)
        XCTAssertEqual(memo.deviceID, 42)
        XCTAssertEqual(resolutions, 1)
    }

    func testRowsBuiltInOnePassShareOneResolution() {
        var resolutions = 0
        var currentDevice: AudioDeviceID = 42
        let memo = CurrentRecordingDeviceMemo {
            resolutions += 1
            return currentDevice
        }

        let rowValues = (0..<8).map { _ -> AudioDeviceID in
            // A change in the middle of a pass must not split the rows between two answers.
            currentDevice += 1
            return memo.deviceID
        }

        XCTAssertEqual(rowValues, Array(repeating: 43, count: 8))
        XCTAssertEqual(resolutions, 1)
    }

    func testLaterPassResolvesAgain() async {
        var resolutions = 0
        var currentDevice: AudioDeviceID = 42
        let memo = CurrentRecordingDeviceMemo {
            resolutions += 1
            return currentDevice
        }

        XCTAssertEqual(memo.deviceID, 42)
        XCTAssertEqual(memo.deviceID, 42)

        currentDevice = 77
        await returnToRunLoop()

        XCTAssertEqual(memo.deviceID, 77)
        XCTAssertEqual(memo.deviceID, 77)
        XCTAssertEqual(resolutions, 2)
    }

    func testMemoIsReleasedWhileItsResetIsPending() async {
        weak var weakMemo: CurrentRecordingDeviceMemo?
        do {
            let memo = CurrentRecordingDeviceMemo { 42 }
            weakMemo = memo
            XCTAssertEqual(memo.deviceID, 42)
        }

        XCTAssertNil(weakMemo, "The pending reset must not keep the memo alive")
        await returnToRunLoop()
    }
}
