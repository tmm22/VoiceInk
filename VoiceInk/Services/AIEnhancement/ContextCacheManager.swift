import Foundation
import os

@MainActor
class ContextCacheManager: ObservableObject {
    static let shared = ContextCacheManager()
    
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "ContextCache")
    
    // Cache Storage
    private var cachedBrowserContext: (context: BrowserContentContext, timestamp: Date)?
    private var cachedCalendarContext: (context: CalendarContext, timestamp: Date)?
    private var cachedScreenContext: (context: ScreenCaptureContext, timestamp: Date)?
    
    // Time To Live Configuration
    // Browser content is relatively static but can change if user navigates. 
    // We'll use a short TTL or rely on the caller to invalidate if they know the URL changed (hard to know without checking).
    // For now, aggressive 30s for browser, 5m for calendar, 10s for screen.
    private let browserTTL: TimeInterval = 30.0
    private let calendarTTL: TimeInterval = 300.0 // 5 minutes
    private let screenTTL: TimeInterval = 10.0
    
    private init() {}
    
    // MARK: - Browser Cache
    
    func getBrowserContext(validatingWith url: String?) -> BrowserContentContext? {
        guard let entry = cachedBrowserContext else { return nil }
        
        // Validation: If URL is provided and doesn't match, invalidate
        if let url = url, entry.context.url != url {
            logger.debug("❌ Cache invalid: URL changed from \(entry.context.url) to \(url)")
            invalidateBrowserCache()
            return nil
        }
        
        if Date().timeIntervalSince(entry.timestamp) < browserTTL {
            logger.debug("✅ Cache hit: Browser Content")
            return entry.context
        }
        cachedBrowserContext = nil
        return nil
    }
    
    func cacheBrowserContext(_ context: BrowserContentContext) {
        cachedBrowserContext = (context, Date())
    }
    
    // MARK: - Calendar Cache
    
    func getCalendarContext() -> CalendarContext? {
        guard let entry = cachedCalendarContext else { return nil }
        if Date().timeIntervalSince(entry.timestamp) < calendarTTL {
            logger.debug("✅ Cache hit: Calendar")
            return entry.context
        }
        cachedCalendarContext = nil
        return nil
    }
    
    func cacheCalendarContext(_ context: CalendarContext) {
        cachedCalendarContext = (context, Date())
    }
    
    // MARK: - Screen Capture Cache
    
    func getScreenContext(validatingWith windowId: String?) -> ScreenCaptureContext? {
        guard let entry = cachedScreenContext else { return nil }
        
        // Validation: If window ID (Title+App) changed, invalidate
        if let windowId = windowId {
            let cachedId = "\(entry.context.applicationName):\(entry.context.windowTitle)"
            if cachedId != windowId {
                logger.debug("❌ Cache invalid: Window changed")
                cachedScreenContext = nil
                return nil
            }
        }
        
        if Date().timeIntervalSince(entry.timestamp) < screenTTL {
            logger.debug("✅ Cache hit: Screen Capture")
            return entry.context
        }
        cachedScreenContext = nil
        return nil
    }
    
    func cacheScreenContext(_ context: ScreenCaptureContext) {
        cachedScreenContext = (context, Date())
    }
    
    // MARK: - Management
    
    func clearAll() {
        cachedBrowserContext = nil
        cachedCalendarContext = nil
        cachedScreenContext = nil
        logger.debug("🗑️ Context cache cleared")
    }
    
    func invalidateBrowserCache() {
        cachedBrowserContext = nil
    }
}
