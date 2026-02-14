import Foundation

enum AppBrand {
    static let primaryName = "VoiceInk"
    static let communityName = "VoiceInk Community"
    static let workspaceTagline = "Community"
    static let supportsInAppUpdates = false

    static var sidebarHeaderTitle: String { primaryName }
    static var sidebarSubtitle: String { workspaceTagline }
    static var releasesURL: URL? { URL(string: "https://github.com/tmm22/VoiceInk/releases") }
}
