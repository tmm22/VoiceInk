import SwiftUI

struct AnimatedCopyButton: View {
    let textToCopy: String
    @State private var isCopied: Bool = false
    
    var body: some View {
        Button {
            copyToClipboard()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(isCopied ? .green : .secondary)
                Text(isCopied ? "Copied" : "Copy")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(isCopied ? .green : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isCopied ? Color.green.opacity(0.4) : Color.primary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isCopied)
    }
    
    private func copyToClipboard() {
        let _ = ClipboardManager.copyToClipboard(textToCopy)
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
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