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
    
    var isEmpty: Bool {
        return (title?.isEmpty ?? true) && 
               (description?.isEmpty ?? true) && 
               (placeholderValue?.isEmpty ?? true) &&
               (value?.isEmpty ?? true)
    }
}

class FocusedElementService {
    static let shared = FocusedElementService()
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "FocusedElementService")
    
    func getFocusedElementInfo() -> FocusedElementInfo? {
        // Check accessibility permissions first
        guard AXIsProcessTrusted() else {
            logger.warning("Accessibility permissions not granted. Cannot fetch focused element.")
            return nil
        }
        
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement as! AXUIElement? else {
            logger.debug("No focused element found.")
            return nil
        }
        
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
        if let val = value, val.count > 500 {
            value = String(val.prefix(500)) + "..."
        }
        
        return FocusedElementInfo(
            role: role,
            roleDescription: roleDescription,
            title: title,
            description: description,
            placeholderValue: placeholder,
            value: value
        )
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
