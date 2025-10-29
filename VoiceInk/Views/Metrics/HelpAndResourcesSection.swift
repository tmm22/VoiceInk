import SwiftUI

struct HelpAndResourcesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Help & Resources")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 12) {
                resourceLink(
                    icon: "book.fill",
                    title: "Community Documentation",
                    url: "https://github.com/tmm22/VoiceInk/wiki"
                )
                
                resourceLink(
                    icon: "exclamationmark.bubble.fill",
                    title: "Report an Issue",
                    url: "https://github.com/tmm22/VoiceInk/issues"
                )
                
                resourceLink(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Join the Discord",
                    url: "https://discord.gg/xryDy57nYD"
                )
            }
        }
        .padding(22)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func resourceLink(icon: String, title: String, url: String) -> some View {
        Button(action: {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 13))
                    .fontWeight(.semibold)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        }
        .buttonStyle(.plain)
    }
}
