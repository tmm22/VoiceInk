import SwiftUI

struct DashboardWindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.visibility = $isVisible
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) {
        view.visibility = $isVisible
    }

    final class VisibilityView: NSView {
        var visibility: Binding<Bool>?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            let name = NSWindow.didChangeOcclusionStateNotification
            center.removeObserver(self, name: name, object: nil)
            if let window {
                center.addObserver(self, selector: #selector(occlusionDidChange(_:)), name: name, object: window)
            }

            // AppKit can attach this view during a SwiftUI update.
            Task { @MainActor [weak self] in
                self?.updateVisibility()
            }
        }

        @objc private func occlusionDidChange(_ notification: Notification) {
            updateVisibility()
        }

        private func updateVisibility() {
            guard let visibility else { return }
            let isVisible = window?.occlusionState.contains(.visible) ?? false
            if visibility.wrappedValue != isVisible {
                visibility.wrappedValue = isVisible
            }
        }
    }
}
