import SwiftUI
import AppKit

extension ConfigurationView {
    @ViewBuilder
    var headerSection: some View {
        HStack {
            Text(mode.title)
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            if case .edit(let config) = mode {
                Button(Localization.PowerMode.deleteAction) {
                    let alert = NSAlert()
                    alert.messageText = Localization.PowerMode.deletePowerModeTitle
                    alert.informativeText = String(format: Localization.PowerMode.deletePowerModeMessage, config.name)
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: Localization.PowerMode.deleteAction)
                    alert.addButton(withTitle: Localization.PowerMode.cancelButton)

                    // Style the Delete button as destructive
                    alert.buttons[0].hasDestructiveAction = true

                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        powerModeManager.removeConfiguration(with: config.id)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .foregroundColor(.red)
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
}
