import Foundation

extension Notification.Name {
    /// Implementation-detail notification emitted by the pinned KeyboardShortcuts package.
    static let keyboardShortcutDidChange = Notification.Name("KeyboardShortcuts_shortcutByNameDidChange")
}
