import XCTest
@testable import VoiceInk

final class RecordingDeviceSwitchTests: XCTestCase {
    enum InjectedFailure: Error { case format, buffers, initialize, start, recovery }

    func testSuccessfulChangeDoesNotRecoverOrStop() throws {
        try RecordingDeviceSwitch.perform(
            change: {}, recover: { XCTFail("Unexpected recovery") },
            stop: { XCTFail("Unexpected stop") }
        )
    }

    func testEverySetupFailureAttemptsRecovery() {
        for failure in [InjectedFailure.format, .buffers, .initialize, .start] {
            var recovered = false
            XCTAssertThrowsError(try RecordingDeviceSwitch.perform(
                change: { throw failure }, recover: { recovered = true },
                stop: { XCTFail("Recovered capture must remain running") }
            )) { error in
                XCTAssertFalse((error as? RecordingDeviceSwitch.Failure)?.recordingStopped ?? true)
            }
            XCTAssertTrue(recovered)
        }
    }

    func testFailedRecoveryStopsBeforeReportingFailure() {
        var stopped = false
        XCTAssertThrowsError(try RecordingDeviceSwitch.perform(
            change: { throw InjectedFailure.start },
            recover: { throw InjectedFailure.recovery }, stop: { stopped = true }
        )) { error in
            XCTAssertTrue(stopped)
            XCTAssertTrue((error as? RecordingDeviceSwitch.Failure)?.recordingStopped ?? false)
        }
    }
}
