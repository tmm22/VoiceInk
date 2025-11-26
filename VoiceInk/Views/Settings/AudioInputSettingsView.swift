import SwiftUI
import CoreAudio

struct AudioInputSettingsView: View {
    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared
    @StateObject private var audioMonitor = AudioLevelMonitor()
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: VoiceInkSpacing.lg) {
            inputModeSection
            
            microphoneTestSection
            
            if audioDeviceManager.inputMode == .custom {
                customDeviceSection
            } else if audioDeviceManager.inputMode == .prioritized {
                prioritizedDevicesSection
            }
        }
        .onDisappear {
            if audioMonitor.isMonitoring {
                audioMonitor.stopMonitoring()
            }
        }
    }
    
    private var inputModeSection: some View {
        VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
            Text("Input Mode")
                .voiceInkHeadline()
            
            HStack(spacing: VoiceInkSpacing.md) {
                ForEach(AudioInputMode.allCases, id: \.self) { mode in
                    InputModeCard(
                        mode: mode,
                        isSelected: audioDeviceManager.inputMode == mode,
                        action: { audioDeviceManager.selectInputMode(mode) }
                    )
                }
            }
        }
    }
    
    private var microphoneTestSection: some View {
        VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
            VStack(alignment: .leading, spacing: VoiceInkSpacing.xxs) {
                Text("Microphone Test")
                    .voiceInkHeadline()
                
                Text("Test your microphone to ensure it's working properly before recording")
                    .voiceInkSubheadline()
            }
            
            VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
                // Test button
                HStack {
                    Button(action: toggleMonitoring) {
                        HStack(spacing: VoiceInkSpacing.xs) {
                            Image(systemName: audioMonitor.isMonitoring ? "stop.circle.fill" : "play.circle.fill")
                            Text(audioMonitor.isMonitoring ? "Stop Test" : "Test Microphone")
                        }
                        .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(audioDeviceManager.isRecordingActive)
                    
                    if audioMonitor.isMonitoring {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Monitoring")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .transition(.opacity)
                    }
                    
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.2), value: audioMonitor.isMonitoring)
                
                // Level meter
                if audioMonitor.isMonitoring {
                    VStack(alignment: .leading, spacing: VoiceInkSpacing.xs) {
                        Text("Input Level")
                            .voiceInkCaptionStyle()
                        
                        // Level bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background
                                RoundedRectangle(cornerRadius: VoiceInkRadius.small)
                                    .fill(VoiceInkTheme.Palette.elevatedSurface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: VoiceInkRadius.small)
                                            .stroke(VoiceInkTheme.Palette.outline, lineWidth: 1)
                                    )
                                
                                // Level bar with gradient
                                let levelWidth = geometry.size.width * CGFloat(audioMonitor.currentLevel)
                                let color = AudioLevelMonitor.levelColor(for: audioMonitor.currentLevel)
                                
                                RoundedRectangle(cornerRadius: VoiceInkRadius.small)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: color.red, green: color.green, blue: color.blue),
                                                Color(red: color.red, green: color.green, blue: color.blue).opacity(0.7)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(0, levelWidth))
                                    .animation(.linear(duration: 0.05), value: audioMonitor.currentLevel)
                            }
                        }
                        .frame(height: 24)
                        
                        // Level description
                        Text(AudioLevelMonitor.levelDescription(for: audioMonitor.currentLevel))
                            .voiceInkCaptionStyle()
                            .accessibilityLabel("Microphone level: \(AudioLevelMonitor.levelDescription(for: audioMonitor.currentLevel))")
                    }
                    .padding(VoiceInkSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                            .fill(VoiceInkTheme.Card.background)
                            .overlay(
                                RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                                    .stroke(VoiceInkTheme.Palette.outline, lineWidth: 1)
                            )
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Error display
                if let error = audioMonitor.error {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    .transition(.opacity)
                }
            }
        }
    }
    
    private func toggleMonitoring() {
        if audioMonitor.isMonitoring {
            audioMonitor.stopMonitoring()
        } else {
            // Get the appropriate device ID to test
            let deviceID: AudioDeviceID?
            
            switch audioDeviceManager.inputMode {
            case .systemDefault:
                deviceID = nil  // Use system default
            case .custom:
                deviceID = audioDeviceManager.selectedDeviceID
            case .prioritized:
                // Use the highest priority available device
                deviceID = audioDeviceManager.getCurrentDevice()
            }
            
            audioMonitor.startMonitoring(deviceID: deviceID)
        }
    }
    
    private var customDeviceSection: some View {
        VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
            HStack {
                Text("Available Devices")
                    .voiceInkHeadline()
                
                Spacer()
                
                Button(action: { audioDeviceManager.loadAvailableDevices() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            
            Text("Note: Selecting a device here will override your Mac's system-wide default microphone.")
                .voiceInkCaptionStyle()
                .padding(.bottom, VoiceInkSpacing.xs)

            VStack(spacing: VoiceInkSpacing.sm) {
                ForEach(audioDeviceManager.availableDevices, id: \.id) { device in
                    DeviceSelectionCard(
                        name: device.name,
                        isSelected: audioDeviceManager.selectedDeviceID == device.id,
                        isActive: audioDeviceManager.getCurrentDevice() == device.id
                    ) {
                        audioDeviceManager.selectDevice(id: device.id)
                    }
                }
            }
        }
    }
    
    private var prioritizedDevicesSection: some View {
        VStack(alignment: .leading, spacing: VoiceInkSpacing.md) {
            if audioDeviceManager.availableDevices.isEmpty {
                emptyDevicesState
            } else {
                prioritizedDevicesContent
                Divider().padding(.vertical, VoiceInkSpacing.xs)
                availableDevicesContent
            }
        }
    }
    
    private var prioritizedDevicesContent: some View {
        VStack(alignment: .leading, spacing: VoiceInkSpacing.sm) {
            VStack(alignment: .leading, spacing: VoiceInkSpacing.xxs) {
                Text("Prioritized Devices")
                    .voiceInkHeadline()
                Text("Devices will be used in order of priority. If a device is unavailable, the next one will be tried. If no prioritized device is available, the system default microphone will be used.")
                    .voiceInkSubheadline()
                    .fixedSize(horizontal: false, vertical: true)
                Text("Warning: Using a prioritized device will override your Mac's system-wide default microphone if it becomes active.")
                    .voiceInkCaptionStyle()
                    .padding(.top, VoiceInkSpacing.xxs)
            }
            
            if audioDeviceManager.prioritizedDevices.isEmpty {
                Text("No prioritized devices")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, VoiceInkSpacing.xs)
            } else {
                prioritizedDevicesList
            }
        }
    }
    
    private var availableDevicesContent: some View {
        VStack(alignment: .leading, spacing: VoiceInkSpacing.sm) {
            Text("Available Devices")
                .voiceInkHeadline()
            
            availableDevicesList
        }
    }
    
    private var emptyDevicesState: some View {
        VStack(spacing: VoiceInkSpacing.md) {
            Image(systemName: "mic.slash.circle.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            
            VStack(spacing: VoiceInkSpacing.xs) {
                Text("No Audio Devices")
                    .voiceInkHeadline()
                Text("Connect an audio input device to get started")
                    .voiceInkSubheadline()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(VoiceInkSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                .fill(VoiceInkTheme.Card.background)
                .overlay(
                    RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                        .stroke(VoiceInkTheme.Palette.outline, lineWidth: 1)
                )
        )
    }
    
    private var prioritizedDevicesList: some View {
        VStack(spacing: VoiceInkSpacing.sm) {
            ForEach(audioDeviceManager.prioritizedDevices.sorted(by: { $0.priority < $1.priority })) { device in
                devicePriorityCard(for: device)
            }
        }
    }
    
    private func devicePriorityCard(for prioritizedDevice: PrioritizedDevice) -> some View {
        let device = audioDeviceManager.availableDevices.first(where: { $0.uid == prioritizedDevice.id })
        return DevicePriorityCard(
            name: prioritizedDevice.name,
            priority: prioritizedDevice.priority,
            isActive: device.map { audioDeviceManager.getCurrentDevice() == $0.id } ?? false,
            isPrioritized: true,
            isAvailable: device != nil,
            canMoveUp: prioritizedDevice.priority > 0,
            canMoveDown: prioritizedDevice.priority < audioDeviceManager.prioritizedDevices.count - 1,
            onTogglePriority: { audioDeviceManager.removePrioritizedDevice(id: prioritizedDevice.id) },
            onMoveUp: { moveDeviceUp(prioritizedDevice) },
            onMoveDown: { moveDeviceDown(prioritizedDevice) }
        )
    }
    
    private var availableDevicesList: some View {
        let unprioritizedDevices = audioDeviceManager.availableDevices.filter { device in
            !audioDeviceManager.prioritizedDevices.contains { $0.id == device.uid }
        }
        
        return Group {
            if unprioritizedDevices.isEmpty {
                Text("No additional devices available")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(unprioritizedDevices, id: \.id) { device in
                    DevicePriorityCard(
                        name: device.name,
                        priority: nil,
                        isActive: audioDeviceManager.getCurrentDevice() == device.id,
                        isPrioritized: false,
                        isAvailable: true,
                        canMoveUp: false,
                        canMoveDown: false,
                        onTogglePriority: { audioDeviceManager.addPrioritizedDevice(uid: device.uid, name: device.name) },
                        onMoveUp: {},
                        onMoveDown: {}
                    )
                }
            }
        }
    }
    
    private func moveDeviceUp(_ device: PrioritizedDevice) {
        guard device.priority > 0,
              let currentIndex = audioDeviceManager.prioritizedDevices.firstIndex(where: { $0.id == device.id })
        else { return }
        
        var devices = audioDeviceManager.prioritizedDevices
        devices.swapAt(currentIndex, currentIndex - 1)
        updatePriorities(devices)
    }
    
    private func moveDeviceDown(_ device: PrioritizedDevice) {
        guard device.priority < audioDeviceManager.prioritizedDevices.count - 1,
              let currentIndex = audioDeviceManager.prioritizedDevices.firstIndex(where: { $0.id == device.id })
        else { return }
        
        var devices = audioDeviceManager.prioritizedDevices
        devices.swapAt(currentIndex, currentIndex + 1)
        updatePriorities(devices)
    }
    
    private func updatePriorities(_ devices: [PrioritizedDevice]) {
        let updatedDevices = devices.enumerated().map { index, device in
            PrioritizedDevice(id: device.id, name: device.name, priority: index)
        }
        audioDeviceManager.updatePriorities(devices: updatedDevices)
    }
}

struct InputModeCard: View {
    let mode: AudioInputMode
    let isSelected: Bool
    let action: () -> Void
    
    private var icon: String {
        switch mode {
        case .systemDefault: return "macbook.and.iphone"
        case .custom: return "mic.circle.fill"
        case .prioritized: return "list.number"
        }
    }
    
    private var description: String {
        switch mode {
        case .systemDefault: return "Use system's default input device"
        case .custom: return "Select a specific input device"
        case .prioritized: return "Set up device priority order"
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: VoiceInkSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? VoiceInkTheme.Palette.accent : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.rawValue)
                        .voiceInkHeadline()
                    
                    Text(description)
                        .voiceInkCaptionStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VoiceInkSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                    .fill(VoiceInkTheme.Card.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                            .stroke(isSelected ? VoiceInkTheme.Card.selectedStroke : VoiceInkTheme.Card.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct DeviceSelectionCard: View {
    let name: String
    let isSelected: Bool
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? VoiceInkTheme.Palette.accent : .secondary)
                    .font(.system(size: 18))
                
                Text(name)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if isActive {
                    Label("Active", systemImage: "wave.3.right")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.green.opacity(0.1))
                        )
                }
            }
            .padding(VoiceInkSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                    .fill(VoiceInkTheme.Card.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                            .stroke(isSelected ? VoiceInkTheme.Card.selectedStroke : VoiceInkTheme.Card.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct DevicePriorityCard: View {
    let name: String
    let priority: Int?
    let isActive: Bool
    let isPrioritized: Bool
    let isAvailable: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onTogglePriority: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    
    var body: some View {
        HStack {
            // Priority number or dash
            if let priority = priority {
                Text("\(priority + 1)")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            } else {
                Text("-")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            
            // Device name
            Text(name)
                .foregroundStyle(isAvailable ? .primary : .secondary)
            
            Spacer()
            
            // Status and Controls
            HStack(spacing: 12) {
                // Active status
                if isActive {
                    Label("Active", systemImage: "wave.3.right")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.green.opacity(0.1))
                        )
                } else if !isAvailable && isPrioritized {
                    Label("Unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(.windowBackgroundColor).opacity(0.4))
                        )
                }
                
                // Priority controls (only show if prioritized)
                if isPrioritized {
                    HStack(spacing: 2) {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .foregroundStyle(canMoveUp ? VoiceInkTheme.Palette.accent : .secondary.opacity(0.5))
                        }
                        .disabled(!canMoveUp)
                        
                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .foregroundStyle(canMoveDown ? VoiceInkTheme.Palette.accent : .secondary.opacity(0.5))
                        }
                        .disabled(!canMoveDown)
                    }
                }
                
                // Toggle priority button
                Button(action: onTogglePriority) {
                    Image(systemName: isPrioritized ? "minus.circle.fill" : "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isPrioritized ? .red : VoiceInkTheme.Palette.accent)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(VoiceInkSpacing.md)
        .background(
             RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                 .fill(VoiceInkTheme.Card.background)
                 .overlay(
                     RoundedRectangle(cornerRadius: VoiceInkRadius.medium)
                         .stroke(VoiceInkTheme.Palette.outline, lineWidth: 1)
                 )
        )
    }
} 
