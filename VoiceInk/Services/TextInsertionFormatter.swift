import Foundation
import AppKit

class TextInsertionFormatter {

    struct InsertionContext {
        let textBefore: String
        let textAfter: String
        let charBeforeCursor: Character?
        let charAfterCursor: Character?
    }

    static func getInsertionContext() -> InsertionContext? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        guard let focusedElement = getFocusedElement() else {
            return nil
        }

        var selectedRange: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange)

        var textValue: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &textValue)

        guard rangeResult == .success,
              textResult == .success,
              let range = selectedRange,
              let text = textValue as? String else {
            return nil
        }

        var rangeValue = CFRange()
        guard AXValueGetValue(range as! AXValue, .cfRange, &rangeValue) else {
            return nil
        }

        let cursorPosition = rangeValue.location
        let beforeStart = max(0, cursorPosition - 100)
        let textBefore = String(text[text.index(text.startIndex, offsetBy: beforeStart)..<text.index(text.startIndex, offsetBy: cursorPosition)])

        let afterEnd = min(text.count, cursorPosition + 100)
        let textAfter = String(text[text.index(text.startIndex, offsetBy: cursorPosition)..<text.index(text.startIndex, offsetBy: afterEnd)])

        let charBefore = cursorPosition > 0 ? text[text.index(text.startIndex, offsetBy: cursorPosition - 1)] : nil
        let charAfter = cursorPosition < text.count ? text[text.index(text.startIndex, offsetBy: cursorPosition)] : nil

        return InsertionContext(
            textBefore: textBefore,
            textAfter: textAfter,
            charBeforeCursor: charBefore,
            charAfterCursor: charAfter
        )
    }

    private static func getFocusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?

        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success else {
            return nil
        }

        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedApp as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return nil
        }

        return (focusedElement as! AXUIElement)
    }

    static func formatTextForInsertion(_ text: String, context: InsertionContext?) -> String {
        guard let context = context else {
            return text + " "
        }

        var formattedText = text
        formattedText = applySmartCapitalization(formattedText, context: context)
        formattedText = applySmartSpacing(formattedText, context: context)

        return formattedText
    }

    private static func applySmartSpacing(_ text: String, context: InsertionContext) -> String {
        var result = text

        if shouldAddSpaceBefore(context: context) {
            result = " " + result
        }

        if let charAfter = context.charAfterCursor {
            if !charAfter.isWhitespace && !charAfter.isPunctuation && !(result.last?.isWhitespace ?? false) {
                result = result + " "
            }
        } else {
            result = result + " "
        }

        return result
    }

    private static func shouldAddSpaceBefore(context: InsertionContext) -> Bool {
        guard let charBefore = context.charBeforeCursor else {
            return false
        }

        if charBefore.isWhitespace {
            return false
        }

        if charBefore == "." || charBefore == "!" || charBefore == "?" {
            return true
        }

        if charBefore == "," || charBefore == ";" || charBefore == ":" || charBefore == "-" {
            return true
        }

        if charBefore.isLetter || charBefore.isNumber {
            return true
        }

        return false
    }

    private static func applySmartCapitalization(_ text: String, context: InsertionContext) -> String {
        guard !text.isEmpty else { return text }

        let shouldCapitalize = shouldCapitalizeFirstLetter(context: context)

        if shouldCapitalize {
            return text.prefix(1).uppercased() + text.dropFirst()
        } else {
            let firstWord = text.prefix(while: { !$0.isWhitespace && !$0.isPunctuation })
            let isAcronymOrProper = firstWord.allSatisfy { $0.isUppercase || !$0.isLetter }

            if !isAcronymOrProper {
                return text.prefix(1).lowercased() + text.dropFirst()
            }
        }

        return text
    }

    private static func shouldCapitalizeFirstLetter(context: InsertionContext) -> Bool {
        if context.textBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        let trimmedBefore = context.textBefore.trimmingCharacters(in: .whitespaces)

        if trimmedBefore.isEmpty {
            return true
        }

        if let lastChar = trimmedBefore.last {
            if lastChar == "." || lastChar == "!" || lastChar == "?" || lastChar == "\n" {
                return true
            }
        }

        return false
    }
}
