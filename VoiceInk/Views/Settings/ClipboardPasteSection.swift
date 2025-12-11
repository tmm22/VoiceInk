import SwiftUI

struct ClipboardPasteSection: View {
    @AppStorage("restoreClipboardAfterPaste") private var restoreClipboardAfterPaste = false
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 1.5
    @AppStorage("UseAppleScriptPaste") private var useAppleScriptPaste = false

    var body: some View {
        VoiceInkSection(
            icon: "doc.on.clipboard",
            title: "Clipboard & Paste",
            subtitle: "Choose how text is pasted and stored"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Toggle("Restore clipboard after paste", isOn: $restoreClipboardAfterPaste)
                        .toggleStyle(.switch)

                    InfoTip(
                        title: "Restore Clipboard",
                        message: "When enabled, \(AppBrand.communityName) will restore your original clipboard content after pasting the transcription."
                    )
                }

                if restoreClipboardAfterPaste {
                    HStack(spacing: 8) {
                        Text("Restore Delay")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)

                        Picker("", selection: $clipboardRestoreDelay) {
                            Text("0.5s").tag(0.5)
                            Text("1.0s").tag(1.0)
                            Text("1.5s").tag(1.5)
                            Text("2.0s").tag(2.0)
                            Text("2.5s").tag(2.5)
                            Text("3.0s").tag(3.0)
                            Text("4.0s").tag(4.0)
                            Text("5.0s").tag(5.0)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 90)

                        Spacer()
                    }
                    .padding(.leading, 16)
                }

                Toggle("Use AppleScript Paste Method", isOn: $useAppleScriptPaste)
                    .toggleStyle(.switch)
                    .help("Use AppleScript if you have a non-standard keyboard layout")
            }
        }
    }
}
