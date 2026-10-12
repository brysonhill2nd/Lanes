import AppKit
import ApplicationServices

// Read-only inspection: no focus, placement, input, or preference writes.
@main struct WindowDiagnostics {
    @MainActor static func main() {
        let manager = WindowManager(startPolling: false)
        let stack = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        print("Accessibility: \(manager.trusted); windows: \(manager.windows.count); front PID: \(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)")
        let nativeStack = manager.focusAccess.stack()
        print("Native focus backend: \(nativeStack.count) window-server entries; \(manager.windows.filter { window in manager.focusAccess.windowID(window).map { id in nativeStack.contains { $0.number == id && $0.pid == window.pid } } ?? false }.count) discovered identities matched")
        for window in manager.windows {
            let app = AXUIElementCreateApplication(window.pid)
            let focused = axValue(app, kAXFocusedWindowAttribute).map { CFEqual($0, window.element) } ?? false
            let number = FrontProcess.windowID(window.element)
            let rank = stack.firstIndex { ($0[kCGWindowNumber as String] as? Int).map(UInt32.init) == number }
            var mainSettable = DarwinBoolean(false), focusSettable = DarwinBoolean(false), windowFocusSettable = DarwinBoolean(false)
            _ = AXUIElementIsAttributeSettable(window.element, kAXMainAttribute as CFString, &mainSettable)
            _ = AXUIElementIsAttributeSettable(app, kAXFocusedWindowAttribute as CFString, &focusSettable)
            _ = AXUIElementIsAttributeSettable(window.element, kAXFocusedAttribute as CFString, &windowFocusSettable)
            print("\(window.id) | \(manager.name(window.lane)) | \(window.appName) | \(window.title) | CG=\(number.map(String.init) ?? "?") rank=\(rank.map(String.init) ?? "offscreen") focused=\(focused) mainWritable=\(mainSettable.boolValue) focusWritable=\(focusSettable.boolValue) windowFocusWritable=\(windowFocusSettable.boolValue) minimized=\(window.minimized) frame=\(window.frame)")
        }
    }
}
