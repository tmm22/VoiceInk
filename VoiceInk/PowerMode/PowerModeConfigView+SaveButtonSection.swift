import SwiftUI

extension ConfigurationView {
    @ViewBuilder
    var saveButtonSection: some View {
        HStack {
            Spacer()
            Button(action: saveConfiguration) {
                Text(mode.isAdding ? Localization.PowerMode.addNewPowerModeLabel : Localization.PowerMode.saveChangesLabel)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(canSave ? Color(red: 0.3, green: 0.7, blue: 0.4) : Color(red: 0.3, green: 0.7, blue: 0.4).opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal)
    }
}
