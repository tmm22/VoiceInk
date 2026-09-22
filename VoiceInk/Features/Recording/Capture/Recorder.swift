import AVFoundation
import Combine
import CoreAudio
import Foundation
import os

@MainActor
class Recorder: NSObject, ObservableObject {
    var recorder: CoreAudioRecorder?
    let logger = Logger(subsystem: AppLogger.subsystem, category: "Recorder")
    let deviceManager = AudioDeviceManager.shared
    private var lifecycleCancellable: AnyCancellable?
    var recordingDeviceChangeObserver: NSObjectProtocol?
    /// The engine saves the partial recording through its normal cancellation path.
    var onRecordingDeviceFailure: (() async -> Void)?
    private let mediaController = MediaController.shared
    private let playbackController = PlaybackController.shared
    /// Dedicated serial queue for hardware setup.
    let audioSetupQueue = DispatchQueue(label: "com.prakashjoshipax.voiceink.audioSetup", qos: .userInitiated)
    private let recordingAudioActionDelayNanoseconds: UInt64 = 220_000_000
    private var audioMuteTask: Task<Void, Never>?
    private var mediaPauseTask: Task<Void, Never>?
    private var audioRestorationTask: Task<Void, Never>?

    /// Normalised (0...1), EMA-smoothed input level, published at `meterUpdateInterval` while recording.
    @Published private(set) var audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
    private var meterUpdateTask: Task<Void, Never>?
    private var smoothedAverage: Float = 0
    private var smoothedPeak: Float = 0
    private let meterUpdateInterval: Duration = .milliseconds(33)
    /// Changes smaller than this are not published; they are invisible at the visualiser's pixel scale.
    private let meterPublishEpsilon: Float = 0.002

    /// Audio chunk callback for streaming. Can be updated while recording;
    /// changes are forwarded to the live CoreAudioRecorder.
    var onAudioChunk: ((_ data: Data) -> Void)? {
        didSet { recorder?.onAudioChunk = onAudioChunk }
    }

    enum RecorderError: Error {
        case couldNotStartRecording
        case noUsableMicrophone(internalMicrophoneBlockedByClosedLid: Bool)
    }

    override init() {
        super.init()
        lifecycleCancellable = LifecycleObserver.shared.publisher(
            for: [.audioDeviceChanged, .systemWillSleep, .systemDidWake]
        ).sink { [weak self] _ in
            Task { @MainActor in
                self?.invalidatePreparedAudioUnit()
            }
        }
        setupRecordingDeviceChangeObserver()
        schedulePrepareForCurrentDevice(reason: "init")
    }

    func startRecording(toOutputFile url: URL) async throws {
        var resolution = deviceManager.resolveCurrentRecordingDevice()
        guard var deviceID = resolution.deviceID else {
            onAudioChunk = nil
            throw RecorderError.noUsableMicrophone(
                internalMicrophoneBlockedByClosedLid: resolution.internalMicrophoneBlockedByClosedLid
            )
        }

        deviceManager.beginRecordingSetup(deviceID: deviceID)

        audioRestorationTask?.cancel()
        audioRestorationTask = nil
        pauseMedia()
        muteSystemAudio()

        let coreAudioRecorder = recorder ?? makeCoreAudioRecorder()
        coreAudioRecorder.onAudioChunk = onAudioChunk
        recorder = coreAudioRecorder

        do {
            do {
                try await startHardwareRecording(coreAudioRecorder, to: url, deviceID: deviceID)
            } catch {
                let retryResolution = deviceManager.resolveCurrentRecordingDevice(excluding: deviceID)
                guard deviceManager.isClamshellClosed,
                    deviceManager.isInternalMicrophone(deviceID),
                    let fallbackDeviceID = retryResolution.deviceID
                else {
                    throw error
                }

                deviceID = fallbackDeviceID
                resolution = retryResolution
                deviceManager.beginRecordingSetup(deviceID: fallbackDeviceID)
                try await startHardwareRecording(coreAudioRecorder, to: url, deviceID: fallbackDeviceID)
            }

            deviceManager.recordingDidStart(deviceID: deviceID)
            showRecordingDeviceNotification(for: deviceID, resolution: resolution)
            UserDefaults.standard.set(String(deviceID), forKey: "lastUsedMicrophoneDeviceID")
            resetAudioMeter()
            startMeterUpdates(for: coreAudioRecorder)
        } catch {
            logger.error(
                "Failed to start recording deviceID=\(deviceID, privacy: .public) file=\(url.lastPathComponent, privacy: .public) error=\(AppLogger.errorMetadata(error), privacy: .public)"
            )
            await stopRecording()
            throw RecorderError.couldNotStartRecording
        }
    }

    func stopRecording() async {
        stopMeterUpdates()
        audioMuteTask?.cancel()
        audioMuteTask = nil
        mediaPauseTask?.cancel()
        mediaPauseTask = nil
        // Capture current recorder to stop it on the serial hardware queue.
        let currentRecorder = self.recorder

        // Normally keep media quiet until capture stops. If a driver stalls, restore it without
        // releasing any audio resources or making the recording available before its file closes.
        var restoredMedia = false
        let mediaRestoreWatchdog = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch { return } // Normal stop cancels this watchdog.
            guard !Task.isCancelled else { return }
            restoredMedia = true
            self?.restoreSystemAudioAfterRecording()
        }
        defer { mediaRestoreWatchdog.cancel() }

        await withCheckedContinuation { continuation in
            audioSetupQueue.async {
                currentRecorder?.stopRecording()
                continuation.resume()
            }
        }
        onAudioChunk = nil

        resetAudioMeter()

        if !restoredMedia { restoreSystemAudioAfterRecording() }
        deviceManager.recordingDidStop()
    }

    private func restoreSystemAudioAfterRecording() {
        audioRestorationTask?.cancel()
        audioRestorationTask = Task { [mediaController, playbackController] in
            await mediaController.unmuteSystemAudio()
            await playbackController.resumeMedia()
        }
    }

    private func muteSystemAudio() {
        audioMuteTask?.cancel()
        audioMuteTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.recordingAudioActionDelayNanoseconds)
            guard !Task.isCancelled else { return }
            _ = await self.mediaController.muteSystemAudio()
        }
    }

    private func pauseMedia() {
        mediaPauseTask?.cancel()
        mediaPauseTask = Task { [weak self] in
            guard let self else { return }
            await self.playbackController.pauseMedia()
        }
    }

    private func schedulePrepareForCurrentDevice(reason: String) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            return
        }

        let deviceID = deviceManager.getCurrentDevice()
        guard deviceID != 0 else {
            let currentRecorder = recorder
            audioSetupQueue.async { currentRecorder?.teardown() }
            return
        }

        let coreAudioRecorder = recorder ?? makeCoreAudioRecorder()
        coreAudioRecorder.onAudioChunk = onAudioChunk
        recorder = coreAudioRecorder

        audioSetupQueue.async { [logger] in
            do {
                try coreAudioRecorder.prepare(deviceID: deviceID)
            } catch {
                logger.warning(
                    "Recorder prepare failed reason=\(reason, privacy: .public) deviceID=\(deviceID, privacy: .public) error=\(AppLogger.errorMetadata(error), privacy: .public)"
                )
            }
        }
    }

    private func invalidatePreparedAudioUnit() {
        guard let coreAudioRecorder = recorder else { return }
        audioSetupQueue.async {
            coreAudioRecorder.invalidatePreparation()
        }
    }

    private func makeCoreAudioRecorder() -> CoreAudioRecorder {
        CoreAudioRecorder(onStalledCallbackDrain: { [weak self] in
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                NotificationManager.shared.showNotification(
                    title: String(localized: "Waiting for the microphone driver to finish. Recording resources are being kept safe."),
                    type: .warning,
                    duration: 10.0
                )
            }
        })
    }

    /// The most recently published meter value. Views should observe `audioMeter` directly.
    func audioMeterSnapshot() -> AudioMeter {
        audioMeter
    }

    // MARK: - Metering

    private func startMeterUpdates(for coreAudioRecorder: CoreAudioRecorder) {
        meterUpdateTask?.cancel()
        // Weak capture: the setup queue must be the last owner of the core so its deinit never runs here.
        meterUpdateTask = Task { [weak self, weak coreAudioRecorder, interval = meterUpdateInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self, let coreAudioRecorder else { return }
                self.updateAudioMeter(
                    averagePowerDb: coreAudioRecorder.averagePower,
                    peakPowerDb: coreAudioRecorder.peakPower
                )
            }
        }
    }

    private func stopMeterUpdates() {
        meterUpdateTask?.cancel()
        meterUpdateTask = nil
    }

    private func updateAudioMeter(averagePowerDb: Float, peakPowerDb: Float) {
        let normalizedAverage = Self.normalizedLevel(fromDecibels: averagePowerDb)
        let normalizedPeak = Self.normalizedLevel(fromDecibels: peakPowerDb)

        // EMA smoothing; snap to zero once the decay is below the publish threshold.
        smoothedAverage = smoothedAverage * 0.6 + normalizedAverage * 0.4
        smoothedPeak = smoothedPeak * 0.6 + normalizedPeak * 0.4
        if normalizedAverage == 0, smoothedAverage < meterPublishEpsilon { smoothedAverage = 0 }
        if normalizedPeak == 0, smoothedPeak < meterPublishEpsilon { smoothedPeak = 0 }

        let candidate = AudioMeter(averagePower: Double(smoothedAverage), peakPower: Double(smoothedPeak))
        guard candidate != audioMeter else { return }

        let averageDelta = abs(Float(candidate.averagePower - audioMeter.averagePower))
        let peakDelta = abs(Float(candidate.peakPower - audioMeter.peakPower))
        let settledToSilence = candidate == AudioMeter(averagePower: 0, peakPower: 0)
        guard averageDelta >= meterPublishEpsilon || peakDelta >= meterPublishEpsilon || settledToSilence else {
            return
        }
        audioMeter = candidate
    }

    /// Maps dBFS onto 0...1 across the visible -60...0 dB window.
    nonisolated static func normalizedLevel(fromDecibels decibels: Float) -> Float {
        let minVisibleDb: Float = -60.0
        let maxVisibleDb: Float = 0.0
        if decibels < minVisibleDb { return 0.0 }
        if decibels >= maxVisibleDb { return 1.0 }
        return (decibels - minVisibleDb) / (maxVisibleDb - minVisibleDb)
    }

    private func resetAudioMeter() {
        smoothedAverage = 0
        smoothedPeak = 0
        let silent = AudioMeter(averagePower: 0, peakPower: 0)
        if audioMeter != silent {
            audioMeter = silent
        }
    }

    // MARK: - Cleanup

    deinit {
        meterUpdateTask?.cancel()
        audioMuteTask?.cancel()
        mediaPauseTask?.cancel()
        audioRestorationTask?.cancel()
        if let observer = recordingDeviceChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        // Retain the core through teardown on the serial hardware queue. Earlier queue closures release
        // their captures before this one runs, main-actor holders live only inside methods that keep
        // `self` alive, `recorder` is never reassigned, and the meter task holds it weakly, so in
        // practice this closure performs the final release and CoreAudioRecorder.deinit runs here.
        let currentRecorder = recorder
        audioSetupQueue.async { currentRecorder?.teardown() }
    }
}

struct AudioMeter: Equatable {
    let averagePower: Double
    let peakPower: Double
}
