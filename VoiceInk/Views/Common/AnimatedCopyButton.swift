import SwiftUI

struct AnimatedCopyButton: View {
    let textToCopy: String
    @State private var isCopied: Bool = false
    
    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                .foregroundStyle(isCopied ? Color.green : .primary)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(isCopied ? "Copied to Clipboard" : "Copy to Clipboard")
        .help(isCopied ? "Copied to Clipboard" : "Copy to Clipboard")
        .animation(.easeInOut(duration: 0.2), value: isCopied)
    }
    
    private func copyToClipboard() {
        let _ = ClipboardManager.copyToClipboard(textToCopy)
        withAnimation {
            isCopied = true
        }
        
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation {
                isCopied = false
            }
        }
    }
}

struct AnimatedCopyButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            AnimatedCopyButton(textToCopy: "Sample text")
            Text("Before Copy")
                .padding()
        }
        .padding()
    }
}
