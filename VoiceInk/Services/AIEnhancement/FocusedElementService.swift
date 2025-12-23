import Foundation
import ApplicationServices
import AppKit
import OSLog

struct FocusedElementInfo: Codable {
    let role: String
    let roleDescription: String
    let title: String?
    let description: String?
    let placeholderValue: String?
    let value: String?
    let textBeforeCursor: String?
    let textAfterCursor: String?
    let nearbyLabels: [String]
    
    var isEmpty: Bool {
        return (title?.isEmpty ?? true) && 
               (description?.isEmpty ?? true) && 
               (placeholderValue?.isEmpty ?? true) &&
               (value?.isEmpty ?? true) &&
               nearbyLabels.isEmpty
    }
}

class FocusedElementService {
    static let shared = FocusedElementService()
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "FocusedElementService")
    
    func getFocusedElementInfo(timeout: TimeInterval = 1.0) async -> FocusedElementInfo? {
        // Check accessibility permissions first (fast check)
        guard AXIsProcessTrusted() else {
            logger.warning("Accessibility permissions not granted. Cannot fetch focused element.")
            return nil
        }
        
        return await withTaskGroup(of: FocusedElementInfo?.self) { group in
            group.addTask {
                let task = Task.detached { [weak self] () -> FocusedElementInfo? in
                    guard let self = self else { return nil }
                    let systemWideElement = AXUIElementCreateSystemWide()
                    var focusedElement: AnyObject?
                    
                    let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
                    
                    guard result == .success, let element = focusedElement as! AXUIElement? else {
                        self.logger.debug("No focused element found.")
                        return nil
                    }
                    
                    return self.extractInfo(from: element)
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
    
    // Kept for backward compatibility if needed, but redirects to async
    func getFocusedElementInfo() -> FocusedElementInfo? {
        logger.warning("Synchronous getFocusedElementInfo called. This may block the main thread. Use async version.")
        // Check permissions
        guard AXIsProcessTrusted() else { return nil }
        
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement as! AXUIElement? else { return nil }
        return extractInfo(from: element)
    }
    
    private func extractInfo(from element: AXUIElement) -> FocusedElementInfo {
        let role = getStringAttribute(element, attribute: kAXRoleAttribute) ?? "Unknown"
        let roleDescription = getStringAttribute(element, attribute: kAXRoleDescriptionAttribute) ?? "Unknown"
        let title = getStringAttribute(element, attribute: kAXTitleAttribute)
        let description = getStringAttribute(element, attribute: kAXDescriptionAttribute)
        let placeholder = getStringAttribute(element, attribute: kAXPlaceholderValueAttribute)
        
        // Be careful with value - it might be large text content
        // We grab a snippet to help understand context (e.g. existing code in editor)
        var value = getStringAttribute(element, attribute: kAXValueAttribute)
        
        // Try to get precise cursor context
        var textBefore: String? = nil
        var textAfter: String? = nil
        
        if let fullText = value, !fullText.isEmpty {
            if let range = getSelectedRange(element) {
                // Safe slicing
                let location = max(0, min(range.location, fullText.count))
                // let length = range.length // We ignore length for insertion point (length 0) logic usually
                
                let startIndex = fullText.index(fullText.startIndex, offsetBy: location)
                
                // Get up to 500 chars before
                let beforeStart = fullText.index(startIndex, offsetBy: -min(500, location))
                textBefore = String(fullText[beforeStart..<startIndex])
                
                // Get up to 500 chars after
                // If selection length > 0, it's "selected text", but here we care about context *surrounding* the insertion point
                // So we start after the selection
                let selectionEndIndex = fullText.index(startIndex, offsetBy: range.length)
                let remainingCount = fullText.distance(from: selectionEndIndex, to: fullText.endIndex)
                let afterEnd = fullText.index(selectionEndIndex, offsetBy: min(500, remainingCount))
                textAfter = String(fullText[selectionEndIndex..<afterEnd])
            }
        }
        
        if let val = value, val.count > 500 {
            value = String(val.prefix(500)) + "..."
        }
        
        // Find nearby labels if we don't have a good title/description
        var nearbyLabels: [String] = []
        if (title?.isEmpty ?? true) && (description?.isEmpty ?? true) {
            nearbyLabels = getSiblingLabels(element)
        }
        
        return FocusedElementInfo(
            role: role,
            roleDescription: roleDescription,
            title: title,
            description: description,
            placeholderValue: placeholder,
            value: value,
            textBeforeCursor: textBefore,
            textAfterCursor: textAfter,
            nearbyLabels: nearbyLabels
        )
    }
    
    private func getSelectedRange(_ element: AXUIElement) -> CFRange? {
        var valueRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &valueRef)
        
        if result == .success,
           let valueRef,
           CFGetTypeID(valueRef) == AXValueGetTypeID() {
            let axValue = valueRef as! AXValue
            if AXValueGetType(axValue) == .cfRange {
                var range = CFRange()
                if AXValueGetValue(axValue, .cfRange, &range) {
                    return range
                }
            }
        }
        return nil
    }
    
    private func getSiblingLabels(_ element: AXUIElement) -> [String] {
        var parentRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef)
        
        guard result == .success, let parentRef else { return [] }
        guard CFGetTypeID(parentRef) == AXUIElementGetTypeID() else { return [] }
        let parent = parentRef as! AXUIElement
        
        var childrenRef: AnyObject?
        let childrenResult = AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &childrenRef)
        
        guard childrenResult == .success, let children = childrenRef as? [AXUIElement] else { return [] }
        
        // Filter for static text elements that are NOT the element itself
        // Limit to 5 labels to avoid noise
        return children.prefix(10).compactMap { child in
            if CFEqual(child, element) { return nil }
            
            let role = getStringAttribute(child, attribute: kAXRoleAttribute)
            if role == "AXStaticText" {
                return getStringAttribute(child, attribute: kAXValueAttribute)
            }
            return nil
        }
    }
    
    private func getStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        
        if result == .success, let stringValue = value as? String, !stringValue.isEmpty {
            return stringValue
        }
        return nil
    }
}
