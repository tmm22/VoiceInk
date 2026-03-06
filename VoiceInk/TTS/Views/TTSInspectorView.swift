import SwiftUI
import AppKit

struct TTSInspectorView: View {
    @EnvironmentObject var viewModel: TTSViewModel
    @Binding var isVisible: Bool

    @State private var isVoiceExpanded = true
    @State private var isAudioExpanded = true
    @State private var isExportExpanded = false
    @State private var isCostExpanded = false
    @State private var isSystemExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    TTSInspectorSection(
                        title: "Voice Configuration",
                        icon: "person.wave.2",
                        isExpanded: $isVoiceExpanded
                    ) {
                        VStack(spacing: 16) {
                            ProviderSelectionView()
                            VoiceSelectionView()
                            VoiceStyleControlsView()
                        }
                    }

                    Divider()

                    TTSInspectorSection(
                        title: "Audio & Playback",
                        icon: "speaker.wave.2",
                        isExpanded: $isAudioExpanded
                    ) {
                        AudioSettingsView()
                    }

                    Divider()

                    TTSInspectorSection(
                        title: "Export",
                        icon: "square.and.arrow.down",
                        isExpanded: $isExportExpanded
                    ) {
                        ExportSettingsView()
                    }

                    Divider()

                    TTSInspectorSection(
                        title: "Cost & Usage",
                        icon: "dollarsign.circle",
                        isExpanded: $isCostExpanded
                    ) {
                        CostView()
                    }

                    Divider()

                    TTSInspectorSection(
                        title: "System",
                        icon: "gear",
                        isExpanded: $isSystemExpanded
                    ) {
                        SystemSettingsView()
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var header: some View {
        HStack {
            Label("Tickwick Settings", systemImage: "slider.horizontal.3")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isVisible = false
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .help("Hide Tickwick Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
