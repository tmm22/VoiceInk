import SwiftUI

extension ConfigurationView {
    @ViewBuilder
    var saveButtonSection: some View {
        HStack {
            Spacer()
            Button(action: saveConfiguration) {
                Text(mode.isAdding ? Localization.PowerMode.addNewPowerModeLabel : Localization.PowerMode.saveChangesLabel)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSave)
        }
        .padding(.horizontal)
    }
}
