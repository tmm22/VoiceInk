import SwiftUI
import SwiftData
import Charts
import KeyboardShortcuts

struct MetricsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transcription.timestamp) private var transcriptions: [Transcription]
    @EnvironmentObject private var whisperState: WhisperState
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @StateObject private var licenseViewModel = LicenseViewModel()
    @State private var hasLoadedData = false
    let skipSetupCheck: Bool
    
    init(skipSetupCheck: Bool = false) {
        self.skipSetupCheck = skipSetupCheck
    }
    
    var body: some View {
        VStack {
            Group {
                if skipSetupCheck {
                    MetricsContent(
                        transcriptions: Array(transcriptions),
                        licenseViewModel: licenseViewModel
                    )
                } else if isSetupComplete {
                    MetricsContent(
                        transcriptions: Array(transcriptions),
                        licenseViewModel: licenseViewModel
                    )
                } else {
                    MetricsSetupView()
                }
            }
        }
        .background(Color(.controlBackgroundColor))
        .task {
            // Ensure the model context is ready
            hasLoadedData = true
        }
    }
    
    private var isSetupComplete: Bool {
        hasLoadedData &&
        whisperState.currentTranscriptionModel != nil &&
        hotkeyManager.selectedHotkey1 != .none &&
        AXIsProcessTrusted() &&
        CGPreflightScreenCaptureAccess()
    }
}
