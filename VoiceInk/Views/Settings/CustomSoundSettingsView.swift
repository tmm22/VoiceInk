import SwiftUI
import UniformTypeIdentifiers

struct CustomSoundSettingsView: View {
    @StateObject private var customSoundManager = CustomSoundManager.shared
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            soundRow(for: .start)
            soundRow(for: .stop)
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    @ViewBuilder
    private func soundRow(for type: CustomSoundManager.SoundType) -> some View {
        horizontalSoundRow(
            title: type.rawValue.capitalized,
            fileName: customSoundManager.getSoundDisplayName(for: type),
            isCustom: type == .start ? customSoundManager.isUsingCustomStartSound : customSoundManager.isUsingCustomStopSound,
            onSelect: { selectSound(for: type) },
            onTest: {
                if type == .start {
                    SoundManager.shared.playStartSound()
                } else {
                    SoundManager.shared.playStopSound()
                }
            },
            onReset: { customSoundManager.resetSoundToDefault(for: type) }
        )
    }

    @ViewBuilder
    private func horizontalSoundRow(
        title: String,
        fileName: String?,
        isCustom: Bool,
        onSelect: @escaping () -> Void,
        onTest: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: 40, alignment: .leading)

            if let fileName = fileName, isCustom {
                Text(fileName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 160, alignment: .leading)

                HStack(spacing: 8) {
                    Button(action: onTest) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Test sound")

                    Button(action: onSelect) {
                        Image(systemName: "folder")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Change sound")

                    Button(action: onReset) {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to default")
                }
            } else {
                Text("Default")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 160, alignment: .leading)

                HStack(spacing: 8) {
                    Button(action: onTest) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Test sound")

                    Button(action: onSelect) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Choose custom sound")
                }
            }
        }
    }

    private func selectSound(for type: CustomSoundManager.SoundType) {
        let panel = NSOpenPanel()
        panel.title = "Choose \(type.rawValue.capitalized) Sound"
        panel.message = "Select an audio file"
        panel.allowedContentTypes = [
            UTType.audio,
            UTType.mp3,
            UTType.wav,
            UTType.aiff
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let result = customSoundManager.setCustomSound(url: url, for: type)
            if case .failure(let error) = result {
                alertTitle = "Invalid Audio File"
                alertMessage = error.localizedDescription
                showingAlert = true
            }
        }
    }
}

#Preview {
    CustomSoundSettingsView()
        .frame(width: 600)
        .padding()
}
