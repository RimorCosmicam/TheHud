import AppKit
import ApplicationServices
import HudCore

/// Plays the phone's cursor and keys back on the Mac as real events.
///
/// Positions arrive as fractions of the streamed picture. For the whole display that is the main
/// display's bounds; for one window it is that window's bounds, looked up each time because a
/// window can be moved while it is being streamed.
@MainActor
final class InputInjector {
    var source: DesktopSource?
    private var pressed = false
    private var lastClick: (time: Date, point: CGPoint, count: Int) = (.distantPast, .zero, 0)

    func perform(_ command: DesktopCommand) {
        switch command {
        case let .move(x, y):
            let point = place(x, y)
            post(pressed ? .leftMouseDragged : .mouseMoved, at: point, button: .left)
        case let .click(x, y, button):
            let point = place(x, y)
            raiseWindow()
            let count = clickCount(at: point)
            let (down, up): (CGEventType, CGEventType) = button == 1
                ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
            post(down, at: point, button: button == 1 ? .right : .left, clicks: count)
            post(up, at: point, button: button == 1 ? .right : .left, clicks: count)
        case let .press(x, y):
            let point = place(x, y)
            raiseWindow()
            pressed = true
            post(.leftMouseDown, at: point, button: .left)
        case let .release(x, y):
            pressed = false
            post(.leftMouseUp, at: place(x, y), button: .left)
        case let .scroll(x, y, dx, dy):
            let point = place(x, y)
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                      wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()),
                                      wheel3: 0) else { return }
            event.location = point
            event.post(tap: .cghidEventTap)
        case let .text(text):
            type(text)
        case let .key(name):
            if let code = Self.keyCodes[name] { press(code) }
        case .select:
            break
        }
    }

    // ------------------------------------------------------------------ geometry

    private func place(_ x: Double, _ y: Double) -> CGPoint {
        let rect = currentRect()
        return CGPoint(x: rect.minX + CGFloat(min(max(x, 0), 1)) * rect.width,
                       y: rect.minY + CGFloat(min(max(y, 0), 1)) * rect.height)
    }

    private func currentRect() -> CGRect {
        if let id = source?.window,
           let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id))
                        as? [[String: Any]])?.first,
           let bounds = info[kCGWindowBounds as String] as? NSDictionary,
           let rect = CGRect(dictionaryRepresentation: bounds) {
            return rect
        }
        return CGDisplayBounds(CGMainDisplayID())
    }

    /// Clicking into a streamed window that is behind others brings it forward first, so the
    /// click lands on it rather than on whatever covers it.
    private func raiseWindow() {
        guard let id = source?.window,
              let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id))
                            as? [[String: Any]])?.first,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t else { return }
        NSRunningApplication(processIdentifier: pid)?.activate()
        let rect = currentRect()
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for window in windows where frame(of: window).map({ $0.equalTo(rect) }) ?? false {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return
        }
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success
        else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }

    // ------------------------------------------------------------------ events

    private func clickCount(at point: CGPoint) -> Int {
        let near = hypot(point.x - lastClick.point.x, point.y - lastClick.point.y) < 6
        let count = near && Date().timeIntervalSince(lastClick.time) < NSEvent.doubleClickInterval
            ? lastClick.count + 1 : 1
        lastClick = (Date(), point, count)
        return count
    }

    private func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton, clicks: Int = 1) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clicks))
        event.post(tap: .cghidEventTap)
    }

    private func type(_ text: String) {
        // Unicode strings go in short runs; a long one is truncated by some apps.
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let chunk = Array(units[index..<min(index + 16, units.count)])
            index += 16
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
                else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    private func press(_ code: CGKeyCode) {
        for down in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)?
                .post(tap: .cghidEventTap)
        }
    }

    private static let keyCodes: [String: CGKeyCode] = [
        "delete": 51, "return": 36, "tab": 48, "escape": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}
