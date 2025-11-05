import Foundation
import AVFoundation
import Combine

/// Errors that can occur during audio level monitoring
enum AudioMonitorError: LocalizedError {
    case deviceSetupFailed
    case invalidFormat
    case engineStartFailed(Error)
    case alreadyMonitoring
    case notMonitoring
    
    var errorDescription: String? {
        switch self {
        case .deviceSetupFailed:
            return "Failed to setup audio device"
        case .invalidFormat:
            return "Invalid audio format"
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .alreadyMonitoring:
            return "Audio monitoring is already active"
        case .notMonitoring:
            return "Audio monitoring is not active"
        }
    }
}

/// Service for monitoring audio input levels in real-time
/// 
/// This service is designed to work alongside the recording pipeline without conflicts.
/// It uses a separate AVAudioEngine instance for testing purposes only.
@MainActor
class AudioLevelMonitor: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current normalized audio level (0.0 to 1.0)
    @Published var currentLevel: Float = 0.0
    
    /// Whether monitoring is currently active
    @Published var isMonitoring = false
    
    /// Current error, if any
    @Published var error: AudioMonitorError?
    
    // MARK: - Private Properties
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var levelUpdateTimer: Timer?
    
    // Audio processing
    private var lastLevel: Float = 0.0
    private let smoothingFactor: Float = 0.3  // Smoothing for visual stability
    
    // MARK: - Initialization
    
    init() {
        // Clean initialization, setup happens on demand
    }
    
    nonisolated deinit {
        // Ensure cleanup - use Task for async work
        Task { @MainActor in
            if isMonitoring {
                stopMonitoring()
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring audio levels from the specified device
    /// - Parameter deviceID: The audio device ID to monitor (nil for default)
    func startMonitoring(deviceID: AudioDeviceID? = nil) {
        guard !isMonitoring else {
            error = .alreadyMonitoring
            return
        }
        
        error = nil
        
        do {
            try setupAudioEngine(deviceID: deviceID)
            isMonitoring = true
            
            // Start level update timer
            levelUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateDisplayLevel()
                }
            }
            
        } catch let monitorError as AudioMonitorError {
            error = monitorError
            isMonitoring = false
            cleanup()
        } catch {
            self.error = .engineStartFailed(error)
            isMonitoring = false
            cleanup()
        }
    }
    
    /// Stop monitoring audio levels and clean up resources
    func stopMonitoring() {
        guard isMonitoring else {
            return
        }
        
        cleanup()
        isMonitoring = false
        currentLevel = 0.0
        lastLevel = 0.0
    }
    
    // MARK: - Private Methods
    
    private func setupAudioEngine(deviceID: AudioDeviceID?) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        
        // Set audio device if specified
        if let deviceID = deviceID {
            #if os(macOS)
            var mutableDeviceID = deviceID
            let size = UInt32(MemoryLayout<AudioDeviceID>.size)
            
            guard let audioUnit = input.audioUnit else {
                throw AudioMonitorError.deviceSetupFailed
            }
            
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &mutableDeviceID,
                size
            )
            
            guard status == noErr else {
                throw AudioMonitorError.deviceSetupFailed
            }
            #endif
        }
        
        // Use the input node's current format to avoid conflicts
        let inputFormat = input.inputFormat(forBus: 0)
        
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioMonitorError.invalidFormat
        }
        
        // Install tap with small buffer for real-time response
        input.installTap(onBus: 0, bufferSize: 512, format: inputFormat) { [weak self] buffer, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.processAudioBuffer(buffer)
            }
        }
        
        // Start the audio engine
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioMonitorError.engineStartFailed(error)
        }
        
        self.audioEngine = engine
        self.inputNode = input
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)
        
        guard frameLength > 0 else { return }
        
        // Calculate RMS (Root Mean Square) for accurate level measurement
        var sum: Float = 0.0
        for frame in 0..<frameLength {
            let sample = channelDataValue[frame]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameLength))
        
        // Convert to dB scale and normalize
        // Reference: -50dB (very quiet) to 0dB (full scale)
        let dB = 20.0 * log10(max(rms, 0.00001))  // Avoid log(0)
        let normalizedLevel = max(0, min(1, (dB + 50.0) / 50.0))
        
        // Store raw level for smoothing
        lastLevel = normalizedLevel
    }
    
    private func updateDisplayLevel() {
        // Apply smoothing for stable visual display
        let smoothedLevel = currentLevel * (1.0 - smoothingFactor) + lastLevel * smoothingFactor
        currentLevel = smoothedLevel
    }
    
    private func cleanup() {
        // Stop timer
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil
        
        // Remove tap
        inputNode?.removeTap(onBus: 0)
        
        // Stop and cleanup engine
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
    }
    
    // MARK: - Helper Methods
    
    /// Get level description for accessibility and user guidance
    /// - Parameter level: The current audio level (0.0 to 1.0)
    /// - Returns: A descriptive string about the level
    static func levelDescription(for level: Float) -> String {
        switch level {
        case 0..<0.05:
            return "No input detected - speak into the microphone"
        case 0.05..<0.15:
            return "Very quiet - try speaking louder"
        case 0.15..<0.30:
            return "Quiet - good for ASMR or soft speech"
        case 0.30..<0.70:
            return "Good level - optimal for transcription"
        case 0.70..<0.85:
            return "Loud - good for noisy environments"
        case 0.85...1.0:
            return "Very loud - may clip, reduce input gain"
        default:
            return "Level: \(Int(level * 100))%"
        }
    }
    
    /// Get color for level visualization
    /// - Parameter level: The current audio level (0.0 to 1.0)
    /// - Returns: A color representing the level quality
    static func levelColor(for level: Float) -> (red: Double, green: Double, blue: Double) {
        switch level {
        case 0..<0.15:
            return (0.6, 0.6, 0.0)  // Yellow (too quiet)
        case 0.15..<0.30:
            return (0.4, 0.8, 0.0)  // Yellow-green (quiet)
        case 0.30..<0.70:
            return (0.0, 0.8, 0.0)  // Green (good)
        case 0.70..<0.85:
            return (1.0, 0.6, 0.0)  // Orange (loud)
        default:
            return (1.0, 0.2, 0.0)  // Red (too loud)
        }
    }
}
