import AppKit
import Combine
import Foundation
import os

/// Runs the context capture for one recording.
///
/// When the recording starts, only the kinds that can be used are captured (see
/// `RecordingContextCaptureKinds.needed`). Mode configurations can still change while the recording
/// or its pipeline is in flight, so the session keeps watching them and captures a skipped kind as
/// soon as a change makes it consumable. Each kind is captured at most once per recording.
@MainActor
final class RecordingContextCaptureSession {
    typealias CaptureStarter = (RecordingContextSnapshotStore, RecordingContextCaptureKinds) -> [Task<Void, Never>]

    let store: RecordingContextSnapshotStore
    private(set) var startedKinds: RecordingContextCaptureKinds = []

    private let canEnhance: Bool
    private let pastesWithSmartPunctuation: Bool
    private let isRecording: () -> Bool
    private let frontmostProcessID: () -> pid_t?
    private let startCapture: CaptureStarter
    private static let logger = Logger(subsystem: AppLogger.subsystem, category: "RecordingContextCapture")

    private var frontmostProcessIDAtStart: pid_t?
    private var tasks: [Task<Void, Never>] = []
    private var configurationObserver: AnyCancellable?

    /// - Parameters:
    ///   - canEnhance: False when this recording can never reach AI enhancement.
    ///   - pastesWithSmartPunctuation: True when the result may be pasted with Smart Punctuation on.
    ///   - isRecording: Whether audio for this recording is still being captured.
    ///   - frontmostProcessID: The process that selected-text capture would read from right now.
    ///   - startCapture: Starts the capture tasks for the given kinds.
    init(
        canEnhance: Bool,
        pastesWithSmartPunctuation: Bool,
        isRecording: @escaping () -> Bool,
        frontmostProcessID: @escaping () -> pid_t?,
        startCapture: @escaping CaptureStarter
    ) {
        self.store = RecordingContextSnapshotStore()
        self.canEnhance = canEnhance
        self.pastesWithSmartPunctuation = pastesWithSmartPunctuation
        self.isRecording = isRecording
        self.frontmostProcessID = frontmostProcessID
        self.startCapture = startCapture
    }

    convenience init(canEnhance: Bool, pastesWithSmartPunctuation: Bool, isRecording: @escaping () -> Bool) {
        self.init(
            canEnhance: canEnhance,
            pastesWithSmartPunctuation: pastesWithSmartPunctuation,
            isRecording: isRecording,
            frontmostProcessID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            startCapture: { store, kinds in
                RecordingContextCaptureService.startCapture(into: store, kinds: kinds)
            }
        )
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

    func start() {
        start(
            configurations: ModeManager.shared.configurations,
            configurationChanges: ModeManager.shared.$configurations.dropFirst().eraseToAnyPublisher()
        )
    }

    /// - Parameters:
    ///   - configurations: Every mode configuration as it is when the recording starts.
    ///   - configurationChanges: Emits the full configuration list each time it changes afterwards.
    func start(
        configurations: [ModeConfig],
        configurationChanges: AnyPublisher<[ModeConfig], Never>
    ) {
        begin(neededKinds(for: configurations))
        Self.logger.debug("Recording context capture started: kinds=\(self.startedKinds.rawValue, privacy: .public)")

        // Nothing can become needed later if this recording never enhances or everything is captured.
        guard canEnhance, startedKinds != .all else { return }

        frontmostProcessIDAtStart = frontmostProcessID()
        configurationObserver = configurationChanges.sink { [weak self] configurations in
            self?.captureNewlyNeededKinds(for: configurations)
        }
    }

    func cancel() {
        configurationObserver = nil
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func neededKinds(for configurations: [ModeConfig]) -> RecordingContextCaptureKinds {
        RecordingContextCaptureKinds.needed(
            for: configurations,
            canEnhance: canEnhance,
            pastesWithSmartPunctuation: pastesWithSmartPunctuation
        )
    }

    private func captureNewlyNeededKinds(for configurations: [ModeConfig]) {
        let missingKinds = neededKinds(for: configurations).subtracting(startedKinds)
        guard !missingKinds.isEmpty else { return }

        let kinds = missingKinds.capturableAfterStart(
            isRecording: isRecording(),
            isFrontmostApplicationUnchanged: frontmostProcessID() == frontmostProcessIDAtStart
        )
        Self.logger.debug(
            "Mode change made context kinds needed mid-recording: missing=\(missingKinds.rawValue, privacy: .public) capturing=\(kinds.rawValue, privacy: .public)"
        )
        begin(kinds)
    }

    private func begin(_ kinds: RecordingContextCaptureKinds) {
        guard !kinds.isEmpty else { return }
        startedKinds.formUnion(kinds)
        tasks.append(contentsOf: startCapture(store, kinds))
    }
}
