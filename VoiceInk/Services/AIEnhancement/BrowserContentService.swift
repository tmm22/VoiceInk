import Foundation
import AppKit
import OSLog

struct BrowserContentContext: Codable {
    let url: String
    let title: String
    let contentSnippet: String
    let browserName: String
}

class BrowserContentService {
    static let shared = BrowserContentService()
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "BrowserContentService")
    
    // Script to get content from Chrome/Brave/Arc (Chromium based)
    private let chromiumScript = """
    tell application "%@"
        if (count of windows) > 0 then
            tell active tab of front window
                set pageTitle to title
                set pageUrl to URL
                set pageContent to execute javascript "document.body.innerText"
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
                set pageContent to text
                return {pageTitle, pageUrl, pageContent}
            end tell
        end if
    end tell
    """
    
    func captureCurrentBrowserContent() async -> BrowserContentContext? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier else { return nil }
        
        let scriptSource: String
        let browserName = app.localizedName ?? "Browser"
        
        if bundleId == "com.apple.Safari" {
            scriptSource = safariScript
        } else if ["com.google.Chrome", "com.brave.Browser", "company.thebrowser.Browser"].contains(bundleId) {
            scriptSource = String(format: chromiumScript, browserName)
        } else {
            return nil
        }
        
        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        
        let result = script.executeAndReturnError(&error)
        
        if let error = error {
            logger.debug("Browser content capture failed: \(error)")
            return nil
        }
        
        // Parse result list {title, url, content}
        if result.numberOfItems == 3,
           let title = result.atIndex(1)?.stringValue,
           let url = result.atIndex(2)?.stringValue,
           let content = result.atIndex(3)?.stringValue {
            
            // Truncate content to avoid token explosion (e.g. 2000 chars)
            // The TokenBudgetManager will handle final truncation, but let's be reasonable here
            let truncatedContent = content.count > 5000 ? String(content.prefix(5000)) + "..." : content
            
            return BrowserContentContext(
                url: url,
                title: title,
                contentSnippet: truncatedContent,
                browserName: browserName
            )
        }
        
        return nil
    }
}
