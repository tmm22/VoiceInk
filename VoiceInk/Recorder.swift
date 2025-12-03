import Foundation
import AVFoundation
import CoreAudio
import os

@MainActor
class Recorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "Recorder")
    private let deviceManager = AudioDeviceManager.shared
    private var deviceObserver: NSObjectProtocol?
    private var isReconfiguring = false
    private let mediaController = MediaController.shared
    private let playbackController = PlaybackController.shared
    @Published var audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
    @Published var recordingDuration: TimeInterval = 0
    private var audioLevelCheckTask: Task<Void, Never>?
    private var audioMeterUpdateTask: Task<Void, Never>?
    private var recordingStartTime: Date?
    private var durationUpdateTask: Task<Void, Never>?
    private var hasDetectedAudioInCurrentSession = false
    
    enum RecorderError: Error {
        case couldNotStartRecording
    }
    
    override init() {
        super.init()
        setupDeviceChangeObserver()
    }
    
    private func setupDeviceChangeObserver() {
        deviceObserver = AudioDeviceConfiguration.createDeviceChangeObserver { [weak self] in
            Task {
                await self?.handleDeviceChange()
            }
        }
    }
    
    private func handleDeviceChange() async {
        guard !isReconfiguring else { return }
        isReconfiguring = true
        
        if recorder != nil {
            let currentURL = recorder?.url
            stopRecording()
            
            if let url = currentURL {
                do {
                    try await startRecording(toOutputFile: url)
                } catch {
                    logger.error("❌ Failed to restart recording after device change: \(error.localizedDescription)")
                }
            }
        }
        isReconfiguring = false
    }
    
    private func configureAudioSession(with deviceID: AudioDeviceID) async throws {
        try AudioDeviceConfiguration.setDefaultInputDevice(deviceID)
    }
    
    func startRecording(toOutputFile url: URL) async throws {
        deviceManager.isRecordingActive = true
        
        let currentDeviceID = deviceManager.getCurrentDevice()
        let lastDeviceID = UserDefaults.standard.string(forKey: "lastUsedMicrophoneDeviceID")
        
        if String(currentDeviceID) != lastDeviceID {
            if let deviceName = deviceManager.availableDevices.first(where: { $0.id == currentDeviceID })?.name {
                // No need for MainActor.run - this class is already @MainActor
                NotificationManager.shared.showNotification(
                    title: String(format: Localization.Recording.usingDevice, deviceName),
                    type: .info
                )
            }
        }
        UserDefaults.standard.set(String(currentDeviceID), forKey: "lastUsedMicrophoneDeviceID")
        
        hasDetectedAudioInCurrentSession = false

        let deviceID = deviceManager.getCurrentDevice()
        if deviceID != 0 {
            do {
                try await configureAudioSession(with: deviceID)
            } catch {
                logger.warning("⚠️ Failed to configure audio session for device \(deviceID), attempting to continue: \(error.localizedDescription)")
            }
        }
        
        let recordSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        do {
            recorder = try AVAudioRecorder(url: url, settings: recordSettings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            
            if recorder?.record() == false {
                logger.error("❌ Could not start recording")
                throw RecorderError.couldNotStartRecording
            }
            
            Task { [weak self] in
                guard let self = self else { return }
                await self.playbackController.pauseMedia()
                _ = await self.mediaController.muteSystemAudio()
            }
            
            audioLevelCheckTask?.cancel()
            audioMeterUpdateTask?.cancel()
            durationUpdateTask?.cancel()
            
            recordingStartTime = Date()
            recordingDuration = 0
            
            audioMeterUpdateTask = Task { [weak self] in
                while let self = self, self.recorder != nil && !Task.isCancelled {
                    self.updateAudioMeter()
                    try? await Task.sleep(nanoseconds: 33_000_000)
                }
            }
            
            durationUpdateTask = Task { [weak self] @MainActor in
                while let self = self, self.recorder != nil && !Task.isCancelled {
                    if let startTime = self.recordingStartTime {
                        // No need for MainActor.run - this task is already @MainActor
                        self.recordingDuration = Date().timeIntervalSince(startTime)
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000) // Update every 0.1 seconds
                }
            }
            
            audioLevelCheckTask = Task { [weak self] @MainActor in
                let notificationChecks: [TimeInterval] = [5.0, 12.0]

                for delay in notificationChecks {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                    if Task.isCancelled { return }

                    guard let self = self else { return }
                    if self.hasDetectedAudioInCurrentSession {
                        return
                    }

                    // No need for MainActor.run - this task is already @MainActor
                    NotificationManager.shared.showNotification(
                        title: Localization.Recording.noAudioDetected,
                        type: .warning
                    )
                }
            }
            
        } catch {
            logger.error("Failed to create audio recorder: \(error.localizedDescription)")
            stopRecording()
            throw RecorderError.couldNotStartRecording
        }
    }
    
    func stopRecording() {
        audioLevelCheckTask?.cancel()
        audioMeterUpdateTask?.cancel()
        durationUpdateTask?.cancel()
        recorder?.stop()
        recorder = nil
        audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
        recordingDuration = 0
        recordingStartTime = nil
        
        Task {
            await mediaController.unmuteSystemAudio()
            try? await Task.sleep(nanoseconds: 100_000_000)
            await playbackController.resumeMedia()
        }
        deviceManager.isRecordingActive = false
    }

    private func updateAudioMeter() {
        guard let recorder = recorder else { return }
        recorder.updateMeters()
        
        let averagePower = recorder.averagePower(forChannel: 0)
        let peakPower = recorder.peakPower(forChannel: 0)
        
        let minVisibleDb: Float = -60.0 
        let maxVisibleDb: Float = 0.0

        let normalizedAverage: Float
        if averagePower < minVisibleDb {
            normalizedAverage = 0.0
        } else if averagePower >= maxVisibleDb {
            normalizedAverage = 1.0
        } else {
            normalizedAverage = (averagePower - minVisibleDb) / (maxVisibleDb - minVisibleDb)
        }
        
        let normalizedPeak: Float
        if peakPower < minVisibleDb {
            normalizedPeak = 0.0
        } else if peakPower >= maxVisibleDb {
            normalizedPeak = 1.0
        } else {
            normalizedPeak = (peakPower - minVisibleDb) / (maxVisibleDb - minVisibleDb)
        }
        
        let newAudioMeter = AudioMeter(averagePower: Double(normalizedAverage), peakPower: Double(normalizedPeak))

        if !hasDetectedAudioInCurrentSession && newAudioMeter.averagePower > 0.01 {
            hasDetectedAudioInCurrentSession = true
        }
        
        audioMeter = newAudioMeter
    }
    
    // MARK: - AVAudioRecorderDelegate
    
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            logger.error("❌ Recording finished unsuccessfully - file may be corrupted or empty")
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: Localization.Recording.fileCorrupted,
                    type: .error
                )
            }
        }
    }
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            logger.error("❌ Recording encode error during session: \(error.localizedDescription)")
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: String(format: Localization.Recording.encodeError, error.localizedDescription),
                    type: .error
                )
            }
        }
    }
    
    deinit {
        recorder?.delegate = nil
        recorder = nil
        audioLevelCheckTask?.cancel()
        audioMeterUpdateTask?.cancel()
        durationUpdateTask?.cancel()
        if let observer = deviceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

struct AudioMeter: Equatable {
    let averagePower: Double
    let peakPower: Double
}