import SwiftUI

extension ConfigurationView {
    @ViewBuilder
    var headerSection: some View {
        HStack {
            Text(mode.title)
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            if case .edit = mode {
                Button(Localization.PowerMode.deleteAction, role: .destructive) {
                    showDeleteConfirmation = true
                }
                .padding(.trailing, 8)
            }

            Button(Localization.PowerMode.cancelButton) {
                presentationMode.wrappedValue.dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 10)
    }

    var editingConfiguration: PowerModeConfig? {
        if case .edit(let config) = mode {
            return config
        }
        return nil
    }

    func deleteCurrentConfiguration() {
        guard let config = editingConfiguration else { return }
        powerModeManager.removeConfiguration(with: config.id)
        presentationMode.wrappedValue.dismiss()
    }
}
