import SwiftUI

extension ConfigurationView {
    @ViewBuilder
    var advancedSection: some View {
        VStack(spacing: 16) {
            SectionHeader(title: Localization.PowerMode.advancedSectionTitle)

            HStack {
                Toggle(Localization.PowerMode.autoSendLabel, isOn: $isAutoSendEnabled)

                InfoTip(
                    title: Localization.PowerMode.autoSendLabel,
                    message: Localization.PowerMode.autoSendMessage
                )

                Spacer()
            }
        }
        .padding()
        .background(CardBackground(isSelected: false))
        .padding(.horizontal)
    }
}
