import Foundation

enum AppBrand {
    static let fallbackBundleIdentifier = "com.tmm22.VoiceLinkCommunity"
    static let primaryName = "VoiceInk"
    static let communityName = "VoiceInk Community"
    static let workspaceTagline = "Community"
    static let supportsInAppUpdates = false
    static let isCommunityEdition = true

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? fallbackBundleIdentifier
    }

    static func applicationSupportDirectory(using fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
            )
        return root.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    static var sidebarHeaderTitle: String { primaryName }
    static var sidebarSubtitle: String { workspaceTagline }
    static var releasesURL: URL? { URL(string: "https://github.com/tmm22/VoiceInk/releases") }
}
