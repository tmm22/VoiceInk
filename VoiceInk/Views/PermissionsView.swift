import SwiftUI
import AVFoundation
import Cocoa
import KeyboardShortcuts

@MainActor
class PermissionManager: ObservableObject {
    @Published var audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var isAccessibilityEnabled = false
    @Published var isScreenRecordingEnabled = false
    @Published var isKeyboardShortcutSet = false
    @Published var isResettingPrivacyPermissions = false
    @Published var privacyPermissionResetMessage: String?
    
    init() {
        // Start observing system events that might indicate permission changes
        setupNotificationObservers()
        
        // Initial permission checks
        checkAllPermissions()
    }
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupNotificationObservers() {
        // Only observe when app becomes active, as this is a likely time for permissions to have changed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func applicationDidBecomeActive() {
        checkAllPermissions()
    }
    
    func checkAllPermissions() {
        checkAccessibilityPermissions()
        checkScreenRecordingPermission()
        checkAudioPermissionStatus()
        checkKeyboardShortcut()
    }
    
    func checkAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
        // No need for DispatchQueue.main.async - this class is already @MainActor
        self.isAccessibilityEnabled = accessibilityEnabled
    }
    
    func checkScreenRecordingPermission() {
        // No need for DispatchQueue.main.async - this class is already @MainActor
        self.isScreenRecordingEnabled = CGPreflightScreenCaptureAccess()
    }
    
    func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }
    
    func checkAudioPermissionStatus() {
        // No need for DispatchQueue.main.async - this class is already @MainActor
        self.audioPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    func requestAudioPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                self?.audioPermissionStatus = granted ? .authorized : .denied
            }
        }
    }
    
    func checkKeyboardShortcut() {
        // No need for DispatchQueue.main.async - this class is already @MainActor
        self.isKeyboardShortcutSet = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) != nil
    }

    func resetPrivacyPermissions() {
        guard !isResettingPrivacyPermissions else { return }

        isResettingPrivacyPermissions = true
        privacyPermissionResetMessage = nil

        Task { [weak self] in
            let outcome = await PermissionResetService.resetCurrentBundlePermissions()
            guard let self else { return }

            self.isResettingPrivacyPermissions = false
            self.privacyPermissionResetMessage = outcome.message

            switch outcome {
            case .succeeded:
                AppSettings.setValue(false, forKey: "hasCompletedOnboarding")
                self.checkAllPermissions()
            case .failed(_, let command, _):
                self.copyToPasteboard(command)
            }
        }
    }

    func copyPermissionResetCommand() {
        let command = PermissionResetService.resetCommand
        copyToPasteboard(command)
        privacyPermissionResetMessage = "Permission reset command copied. Paste it into Terminal, then quit and reopen VoiceInk."
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let buttonTitle: String
    let buttonAction: () -> Void
    let checkPermission: () -> Void
    var infoTipMessage: String?
    var infoTipLink: String?
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                // Icon with background
                ZStack {
                    Circle()
                        .fill(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: isGranted ? "\(icon).fill" : icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isGranted ? .green : .orange)
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.headline)
                        if let message = infoTipMessage {
                            if let link = infoTipLink, !link.isEmpty {
                                InfoTip(message, learnMoreURL: link)
                            } else {
                                InfoTip(message)
                            }
                        }
                    }
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status indicator with refresh
                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isRefreshing = true
                        }
                        checkPermission()
                        
                        // Reset the animation after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isRefreshing = false
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 20, minHeight: 20)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Refresh \(title) status")
                    .help("Refresh \(title) status")
                    
                    if isGranted {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                            .symbolRenderingMode(.hierarchical)
                            .accessibilityLabel("\(title) granted")
                    } else {
                        Image(systemName: "xmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.orange)
                            .symbolRenderingMode(.hierarchical)
                            .accessibilityLabel("\(title) not granted")
                    }
                }
            }
            
            if !isGranted {
                Button(action: buttonAction) {
                    Label(buttonTitle, systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help(buttonTitle)
            }
        }
        .padding()
        .background(CardBackground(isSelected: false))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
    }
}

struct PermissionsView: View {
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @StateObject private var permissionManager = PermissionManager()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 24) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                        .padding(20)
                        .background(Circle()
                            .fill(Color(.windowBackgroundColor).opacity(0.9))
                            .shadow(color: .black.opacity(0.1), radius: 10, y: 5))
                        .accessibilityHidden(true)
                    
                    VStack(spacing: 8) {
                        Text("App Permissions")
                            .font(.system(size: 28, weight: .bold))
                        Text("\(AppBrand.communityName) requires the following permissions to function properly")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)

                permissionRepairCard
                
                // Permission Cards
                VStack(spacing: 16) {
                    // Keyboard Shortcut Permission
                    PermissionCard(
                        icon: "keyboard",
                        title: "Keyboard Shortcut",
                        description: "Set up a keyboard shortcut to use \(AppBrand.communityName) anywhere",
                        isGranted: hotkeyManager.selectedHotkey1 != .none,
                        buttonTitle: "Configure Shortcut",
                        buttonAction: {
                            NotificationCenter.default.post(
                                name: .navigateToDestination,
                                object: nil,
                                userInfo: ["destination": "Settings"]
                            )
                        },
                        checkPermission: { permissionManager.checkKeyboardShortcut() }
                    )
                    
                    // Audio Permission
                    PermissionCard(
                        icon: "mic",
                        title: "Microphone Access",
                        description: "Allow \(AppBrand.communityName) to record your voice for transcription",
                        isGranted: permissionManager.audioPermissionStatus == .authorized,
                        buttonTitle: permissionManager.audioPermissionStatus == .notDetermined ? "Request Permission" : "Open System Settings",
                        buttonAction: {
                            if permissionManager.audioPermissionStatus == .notDetermined {
                                permissionManager.requestAudioPermission()
                            } else {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        },
                        checkPermission: { permissionManager.checkAudioPermissionStatus() }
                    )
                    
                    // Accessibility Permission
                    PermissionCard(
                        icon: "hand.raised",
                        title: "Accessibility Access",
                        description: "Allow \(AppBrand.communityName) to paste transcribed text directly at your cursor position",
                        isGranted: permissionManager.isAccessibilityEnabled,
                        buttonTitle: "Open System Settings",
                        buttonAction: {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        },
                        checkPermission: { permissionManager.checkAccessibilityPermissions() },
                        infoTipMessage: "\(AppBrand.communityName) uses Accessibility permissions to paste the transcribed text directly into other applications at your cursor's position. This allows for a seamless dictation experience across your Mac."
                    )
                    
                    // Screen Recording Permission
                    PermissionCard(
                        icon: "rectangle.on.rectangle",
                        title: "Screen Recording Access",
                        description: "Allow \(AppBrand.communityName) to understand context from your screen for transcript Enhancement",
                        isGranted: permissionManager.isScreenRecordingEnabled,
                        buttonTitle: "Request Permission",
                        buttonAction: {
                            permissionManager.requestScreenRecordingPermission()
                            // After requesting, open system preferences as fallback
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        },
                        checkPermission: { permissionManager.checkScreenRecordingPermission() },
                        infoTipMessage: "\(AppBrand.communityName) captures on-screen text to understand the context of your voice input, which significantly improves transcription accuracy. Your privacy is important: this data is processed locally and is not stored.",
                        infoTipLink: "https://tryvoiceink.com/docs/contextual-awareness"
                    )
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            permissionManager.checkAllPermissions()
        }
    }

    private var permissionRepairCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Permissions stopped working after an update?")
                        .font(.headline)
                    Text("Unsigned community updates can leave stale macOS privacy records behind. Reset the records, then quit and reopen VoiceInk to grant Microphone, Accessibility, Screen Recording, and other permissions again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                Button {
                    permissionManager.resetPrivacyPermissions()
                } label: {
                    if permissionManager.isResettingPrivacyPermissions {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Reset Permission Records", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(permissionManager.isResettingPrivacyPermissions)

                Button {
                    permissionManager.copyPermissionResetCommand()
                } label: {
                    Label("Copy Terminal Command", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }

            if let message = permissionManager.privacyPermissionResetMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(CardBackground(isSelected: false))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
    }
}

#Preview {
    PermissionsView()
} 
