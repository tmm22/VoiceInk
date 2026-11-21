import AppKit
import CoreGraphics
import XCTest
@testable import VoiceInk

/// The global shortcut tap is an active tap, so every event in its mask waits for this process.
/// It must ask for mouse-button events only when a mouse-button shortcut exists.
final class ShortcutMonitorEventMaskTests: XCTestCase {
    private let keyShortcut = Shortcut.key(keyCode: 49, modifierFlags: [.option])
    private let modifierShortcut = Shortcut.modifierOnly(keyCode: 61, modifierFlags: [.option])
    private let mouseShortcut = Shortcut.mouseButton(buttonNumber: 3)

    private var keyEvents: CGEventMask {
        bit(.keyDown) | bit(.keyUp) | bit(.flagsChanged)
    }

    private var otherMouseEvents: CGEventMask {
        bit(.otherMouseDown) | bit(.otherMouseDragged) | bit(.otherMouseUp)
    }

    func testKeyAndModifierShortcutsListenToKeyEventsOnly() {
        XCTAssertEqual(ShortcutMonitor.eventMask(for: [keyShortcut]), keyEvents)
        XCTAssertEqual(ShortcutMonitor.eventMask(for: [modifierShortcut]), keyEvents)
        XCTAssertEqual(ShortcutMonitor.eventMask(for: [keyShortcut, modifierShortcut]), keyEvents)
    }

    func testNoShortcutsStillListenToKeyEvents() {
        XCTAssertEqual(ShortcutMonitor.eventMask(for: [Shortcut]()), keyEvents)
    }

    func testAMouseButtonShortcutAddsOtherMouseButtonEvents() {
        let expected = keyEvents | otherMouseEvents

        XCTAssertEqual(ShortcutMonitor.eventMask(for: [mouseShortcut]), expected)
        XCTAssertEqual(ShortcutMonitor.eventMask(for: [keyShortcut, mouseShortcut, modifierShortcut]), expected)
        XCTAssertEqual(ShortcutMonitor.eventMask(for: [modifierShortcut, mouseShortcut]), expected)
    }

    func testPrimaryButtonsMovementAndScrollingAreNeverIntercepted() {
        let neverIntercepted: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .mouseMoved, .scrollWheel,
        ]

        for shortcuts in [[keyShortcut], [mouseShortcut], [keyShortcut, mouseShortcut, modifierShortcut]] {
            let mask = ShortcutMonitor.eventMask(for: shortcuts)
            for type in neverIntercepted {
                XCTAssertEqual(mask & bit(type), 0, "event type \(type.rawValue) must not be in the mask")
            }
        }
    }

    private func bit(_ type: CGEventType) -> CGEventMask {
        CGEventMask(1) << Int(type.rawValue)
    }
}
