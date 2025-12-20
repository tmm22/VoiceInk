import Foundation
import AppKit
import OSLog

struct BrowserContentContext: Codable {
    let url: String
    let title: String
    let contentSnippet: String
    let browserName: String
    /// Indicates whether full content extraction was available for this browser
    let isContentAvailable: Bool
    
    /// Backward-compatible initializer (defaults isContentAvailable to true)
    init(url: String, title: String, contentSnippet: String, browserName: String, isContentAvailable: Bool = true) {
        self.url = url
        self.title = title
        self.contentSnippet = contentSnippet
        self.browserName = browserName
        self.isContentAvailable = isContentAvailable
    }
}

class BrowserContentService {
    static let shared = BrowserContentService()
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "BrowserContentService")
    
    // MARK: - Browser Categories
    
    /// Categorizes browsers by their content extraction capability
    private enum BrowserCategory {
        case safari           // Uses Safari-specific API (document.text property)
        case chromiumFull     // Chromium with full JS execution (Chrome, Brave, Arc)
        case chromiumOther    // Other Chromium browsers (Edge, Opera, Vivaldi, Yandex)
        case webkitOrion      // Orion - WebKit-based but different API than Safari
        case firefoxLimited   // Firefox/Zen - title only via window name, no content extraction
        case unsupported      // Unknown browsers
        
        static func from(bundleId: String) -> BrowserCategory {
            switch bundleId {
            case "com.apple.Safari":
                return .safari
            case "com.google.Chrome", "com.brave.Browser", "company.thebrowser.Browser":
                return .chromiumFull
            case "com.microsoft.edgemac", "com.operasoftware.Opera",
                 "com.vivaldi.Vivaldi", "ru.yandex.desktop.yandex-browser":
                return .chromiumOther
            case "com.kagi.kagimacOS":
                return .webkitOrion
            case "org.mozilla.firefox", "app.zen-browser.zen":
                return .firefoxLimited
            default:
                return .unsupported
            }
        }
        
        var supportsContentExtraction: Bool {
            switch self {
            case .safari, .chromiumFull, .chromiumOther, .webkitOrion:
                return true
            case .firefoxLimited, .unsupported:
                return false
            }
        }
    }
    
    // MARK: - AppleScript Templates
    
    // Script to get content from Chrome/Brave/Arc (Chromium based)
    private let chromiumScript = """
    tell application "%@"
        if (count of windows) > 0 then
            tell active tab of front window
                set pageTitle to title
                set pageUrl to URL
                set pageContent to execute javascript "document.body && document.body.innerText ? document.body.innerText.substring(0, 5000) : ''"
                return {pageTitle, pageUrl, pageContent}
            end tell
        end if
    end tell
    """
    
    // Script for Safari
    private let safariScript = """
    tell application "Safari"
        if (count of documents) > 0 then
            tell front document
                set pageTitle to name
                set pageUrl to URL
                set pageContent to do JavaScript "document.body && document.body.innerText ? document.body.innerText.substring(0, 5000) : ''"
                return {pageTitle, pageUrl, pageContent}
            end tell
        end if
    end tell
    """
    
    // Script for other Chromium-based browsers that support JavaScript execution
    // Works with: Edge, Opera, Vivaldi, Yandex
    private let chromiumJSScript = """
    tell application "%@"
        if (count of windows) > 0 then
            tell active tab of front window
                set pageTitle to title
                set pageUrl to URL
                set pageContent to execute javascript "document.body && document.body.innerText ? document.body.innerText.substring(0, 5000) : ''"
                return {pageTitle, pageUrl, pageContent}
            end tell
        end if
    end tell
    """
    
    // Script for Orion (WebKit-based, similar structure to Arc)
    private let orionScript = """
    tell application "Orion"
        if (count of windows) > 0 then
            tell front window
                tell active tab
                    set pageTitle to name
                    set pageUrl to URL
                    set pageContent to execute javascript "document.body && document.body.innerText ? document.body.innerText.substring(0, 5000) : ''"
                    return {pageTitle, pageUrl, pageContent}
                end tell
            end tell
        end if
    end tell
    """
    
    // Script for Firefox/Zen - Limited: Only window title available
    // Content extraction not supported due to AppleScript limitations
    private let firefoxLimitedScript = """
    tell application "%@"
        if (count of windows) > 0 then
            set windowName to name of front window
            return {windowName, "", ""}
        end if
    end tell
    """
    
    func captureCurrentBrowserContent(timeout: TimeInterval = 2.0) async -> BrowserContentContext? {
        // Capture app info on MainActor before detaching
        guard let app = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication }),
              let bundleId = app.bundleIdentifier else { return nil }
        
        let browserName = app.localizedName ?? "Browser"
        let category = BrowserCategory.from(bundleId: bundleId)
        
        // Skip unsupported browsers entirely
        guard category != .unsupported else {
            logger.debug("Unsupported browser for content extraction: \(bundleId)")
            return nil
        }
        
        let scriptSource: String
        
        switch category {
        case .safari:
            scriptSource = safariScript
        case .chromiumFull:
            scriptSource = String(format: chromiumScript, browserName)
        case .chromiumOther:
            scriptSource = String(format: chromiumJSScript, browserName)
        case .webkitOrion:
            scriptSource = orionScript
        case .firefoxLimited:
            // For Firefox/Zen, try to get at least title from window name
            scriptSource = String(format: firefoxLimitedScript, browserName)
        case .unsupported:
            return nil
        }
        
        // Execute on background thread with timeout
        return await withTaskGroup(of: BrowserContentContext?.self) { group in
            group.addTask { [weak self] in
                guard let self = self else { return nil }
                let task = Task.detached {
                    return self.executeScript(
                        source: scriptSource,
                        browserName: browserName,
                        category: category
                    )
                }
                return await task.value
            }
            
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil // Timeout
            }
            
            if let result = await group.next() {
                return result
            }
            return nil
        }
    }
    
    private func executeScript(
        source: String,
        browserName: String,
        category: BrowserCategory = .chromiumFull
    ) -> BrowserContentContext? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            logger.error("Failed to create AppleScript for \(browserName)")
            return nil
        }
        
        let result = script.executeAndReturnError(&error)
        
        if let error = error {
            // Log but don't fail - common for AppleEvents timeout/cancel
            logger.debug("AppleScript error for \(browserName): \(error)")
            return nil
        }
        
        // Handle Firefox/Zen limited response (just window title)
        if category == .firefoxLimited {
            if let windowTitle = result.atIndex(1)?.stringValue, !windowTitle.isEmpty {
                // Parse title - Firefox typically shows "Page Title — Mozilla Firefox"
                // Zen shows "Page Title — Zen Browser"
                let titleComponents = windowTitle.components(separatedBy: " — ")
                let title = titleComponents.first ?? windowTitle
                
                logger.info("Firefox/Zen: Retrieved title only (content extraction not supported)")
                
                return BrowserContentContext(
                    url: "",  // Not available via AppleScript
                    title: title,
                    contentSnippet: "[Content extraction not supported for \(browserName). Only page title is available for AI context.]",
                    browserName: browserName,
                    isContentAvailable: false
                )
            }
            return nil
        }
        
        // Parse standard result list {title, url, content}
        if result.numberOfItems == 3,
           let title = result.atIndex(1)?.stringValue,
           let url = result.atIndex(2)?.stringValue,
           let content = result.atIndex(3)?.stringValue {
            
            // Truncate content to avoid token explosion (e.g. 5000 chars)
            let truncatedContent = content.count > 5000 ? String(content.prefix(5000)) + "..." : content
            
            return BrowserContentContext(
                url: url,
                title: title,
                contentSnippet: truncatedContent,
                browserName: browserName,
                isContentAvailable: true
            )
        }
        
        logger.debug("Failed to parse AppleScript result for \(browserName)")
        return nil
    }
}
