import SwiftUI

/// A reusable info tip component that displays helpful information in a popover
struct InfoTip: View {
    // Content configuration
    var title: String? = nil
    var message: String
    var learnMoreLink: URL?
    var learnMoreText: String = Localization.General.learnMore

    // Appearance customization
    var iconName: String = "info.circle.fill"
    var iconSize: Image.Scale = .medium
    var iconColor: Color = .primary
    var width: CGFloat = 280

    // State
    @State private var isShowingTip: Bool = false

    var body: some View {
        Image(systemName: iconName)
            .imageScale(iconSize)
            .foregroundColor(iconColor)
            .fontWeight(.semibold)
            .padding(5)
            .contentShape(Rectangle())
            .popover(isPresented: $isShowingTip) {
                VStack(alignment: .leading, spacing: 10) {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let url = learnMoreLink {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Text(learnMoreText)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Image(systemName: "arrow.up.forward")
                                    .font(.caption2)
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .frame(width: width, alignment: .leading)
            }
            .onTapGesture {
                isShowingTip.toggle()
            }
    }
}

// MARK: - Convenience initializers

extension InfoTip {
    /// Creates an InfoTip with title and message
    init(title: String, message: String, learnMoreURL: String? = nil) {
        self.title = title
        self.message = message
        self.learnMoreLink = learnMoreURL.flatMap(URL.init(string:))
    }

    /// Creates an InfoTip with just a message
    init(_ message: String) {
        self.title = nil
        self.message = message
        self.learnMoreLink = nil
    }

    /// Creates an InfoTip with a learn more link
    init(_ message: String, learnMoreURL: String) {
        self.title = nil
        self.message = message
        self.learnMoreLink = URL(string: learnMoreURL)
    }
}
