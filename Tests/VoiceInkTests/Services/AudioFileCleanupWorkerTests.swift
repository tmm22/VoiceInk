import XCTest
@testable import VoiceInk

final class AudioFileCleanupWorkerTests: XCTestCase {
    func testDeletesFilesInsideAllowedRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("recording.wav")
        try Data([1, 2, 3]).write(to: file)

        let result = await AudioFileCleanupWorker().delete(
            [AudioFileCandidate(id: UUID(), url: file)],
            allowedRoot: root
        )

        guard case .deleted = result.first?.deletion else {
            return XCTFail("Expected file to be deleted")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRefusesToDeleteFileOutsideAllowedRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1]).write(to: outside)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let result = await AudioFileCleanupWorker().delete(
            [AudioFileCandidate(id: UUID(), url: outside)],
            allowedRoot: root
        )

        guard case .failed = result.first?.deletion else {
            return XCTFail("Expected out-of-root deletion to be refused")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testRefusesSymlinkEscapeFromAllowedRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        let link = root.appendingPathComponent("recording.wav")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1]).write(to: outside)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let result = await AudioFileCleanupWorker().delete(
            [AudioFileCandidate(id: UUID(), url: link)],
            allowedRoot: root
        )

        guard case .failed = result.first?.deletion else {
            return XCTFail("Expected symlink escape to be refused")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
}
