import SwiftUI
import AppKit

struct DashboardPromotionsSection: View {
    let licenseState: LicenseViewModel.LicenseState
    
    private var shouldShowUpgradePromotion: Bool {
        guard case .trial(let daysRemaining) = licenseState else { return false }
        return daysRemaining <= 9
    }
    
    private var shouldShowAffiliatePromotion: Bool {
        if case .licensed = licenseState {
            return true
        }
        return false
    }
    
    private var shouldShowPromotions: Bool {
        shouldShowUpgradePromotion || shouldShowAffiliatePromotion
    }
    
    var body: some View {
        if shouldShowPromotions {
            HStack(alignment: .top, spacing: 18) {
                if shouldShowUpgradePromotion {
                    DashboardPromotionCard(
                        badge: "30% OFF",
                        title: "Share VoiceInk, Save 30%",
                        message: "Tell your audience about VoiceInk on social and unlock a 30% discount on VoiceInk Pro when they upgrade.",
                        gradient: LinearGradient(
                            colors: [
                                Color(red: 0.08, green: 0.48, blue: 0.85),
                                Color(red: 0.05, green: 0.18, blue: 0.42)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        accentSymbol: "megaphone.fill",
                        glowColor: Color(red: 0.08, green: 0.48, blue: 0.85),
                        actionTitle: "Share & Unlock",
                        actionIcon: "arrow.up.right",
                        action: openSocialShare
                    )
                    .frame(maxWidth: .infinity)
                }
                
                if shouldShowAffiliatePromotion {
                    DashboardPromotionCard(
                        badge: "AFFILIATE 30%",
                        title: "Earn With The VoiceInk Affiliate Program",
                        message: "Share VoiceInk with friends or your audience and receive 30% on every referral that upgrades.",
                        gradient: LinearGradient(
                            colors: [
                                Color(red: 0.08, green: 0.48, blue: 0.85),
                                Color(red: 0.05, green: 0.18, blue: 0.42)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        accentSymbol: "link.badge.plus",
                        glowColor: Color(red: 0.08, green: 0.48, blue: 0.85),
                        actionTitle: "Explore Affiliate",
                        actionIcon: "arrow.up.right",
                        action: openAffiliateProgram
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            EmptyView()
        }
    }
    
    private func openSocialShare() {
        if let url = URL(string: "https://tryvoiceink.com/social-share") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openAffiliateProgram() {
        if let url = URL(string: "https://tryvoiceink.com/affiliate") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct DashboardPromotionCard: View {
    let badge: String
    let title: String
    let message: String
    let gradient: LinearGradient
    let accentSymbol: String
    let glowColor: Color
    let actionTitle: String
    let actionIcon: String
    let action: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(message)
                .font(.system(size: 13.5, weight: .medium))
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
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(gradient)
                .overlay {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.12))
                            .frame(width: 140, height: 140)
                            .offset(x: 60, y: -60)
                        Circle()
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                            .frame(width: 170, height: 170)
                            .offset(x: -40, y: 70)
                    }
                    .clipped()
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: glowColor.opacity(0.28), radius: 24, x: 0, y: 14)
    }
}
