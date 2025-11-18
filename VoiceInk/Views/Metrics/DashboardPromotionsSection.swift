import SwiftUI
import AppKit

struct DashboardPromotionsSection: View {
    let licenseState: LicenseViewModel.LicenseState
    
    var body: some View {
        switch licenseState {
        case .communityEdition:
            communityEditionPromotions
        }
    }
    
    private var communityEditionPromotions: some View {
        HStack(alignment: .top, spacing: 18) {
            DashboardPromotionCard(
                badge: "COMMUNITY",
                title: "Support \(AppBrand.communityName)",
                message: "Star the project on GitHub or contribute improvements to help the community edition thrive.",
                accentSymbol: "hands.sparkles.fill",
                glowColor: Color(nsColor: .controlAccentColor),
                actionTitle: "Open GitHub",
                actionIcon: "arrow.up.right",
                action: openRepository
            )
            .frame(maxWidth: .infinity)
            
            DashboardPromotionCard(
                badge: "CONNECT",
                title: "Join The Conversation",
                message: "Share workflows, ask questions, and connect with other contributors in the community Discord.",
                accentSymbol: "bubble.left.and.bubble.right.fill",
                glowColor: Color(red: 0.32, green: 0.45, blue: 0.91),
                actionTitle: "Join Discord",
                actionIcon: "arrow.up.right",
                action: openCommunity
            )
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func openRepository() {
        if let url = URL(string: "https://github.com/tmm22/VoiceInk") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openCommunity() {
        if let url = URL(string: "https://discord.gg/xryDy57nYD") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct DashboardPromotionCard: View {
    let badge: String
    let title: String
    let message: String
    let accentSymbol: String
    let glowColor: Color
    let actionTitle: String
    let actionIcon: String
    let action: () -> Void
    
    private static let defaultGradient: LinearGradient = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.48, blue: 0.85),
            Color(red: 0.05, green: 0.18, blue: 0.42)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(badge.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: accentSymbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(10)
                    .background(.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text(title)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: action) {
                HStack(spacing: 6) {
                    Text(actionTitle)
                    Image(systemName: actionIcon)
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.white.opacity(0.22))
                .clipShape(Capsule())
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Self.defaultGradient)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: glowColor.opacity(0.15), radius: 12, x: 0, y: 8)
    }
}
