import AppKit
import SwiftUI

@main struct NativeHoverTests {
    @MainActor static func main() {
        let view = LaneScrollHostingView(rootView: AnyView(Color.clear))
        view.frame = CGRect(x: 0, y: 0, width: 620, height: 56)
        var hovered: [Bool] = []
        view.onHover = { hovered.append($0) }
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: CGPoint(x: 10, y: 10), modifierFlags: [], timestamp: 1,
                windowNumber: 0, context: nil, eventNumber: 1, trackingNumber: 1, userData: nil)!
        }
        precondition(view.acceptsFirstMouse(for: nil), "window tabs must accept the first click without activating Lanes")
        view.updateTrackingAreas()
        precondition(view.trackingAreas.contains { $0.options.contains(.activeAlways) && $0.options.contains(.inVisibleRect) }, "hover must work while another app is active")
        let visibility = StripVisibility(idleDelay: 0.02, fadeDuration: 0.02)
        visibility.start()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        precondition(!visibility.visible, "idle bars fade all the way out")
        visibility.setHovered(true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        precondition(visibility.visible, "hover restores the bar and cancels its idle fade")
        visibility.setHovered(false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        precondition(!visibility.visible, "leaving the bar fades it again")
        visibility.start()
        precondition(!visibility.visible, "content refreshes must not reveal idle bars")
        visibility.setHovered(true); visibility.setHovered(false); visibility.cancel()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        precondition(visibility.visible, "removed views cancel pending fade callbacks")
        view.mouseEntered(with: event(.mouseEntered))
        view.mouseExited(with: event(.mouseExited))
        precondition(hovered == [true, false], "entering and leaving the category strip must scope its keyboard shortcuts")
        var switched: [Int] = []
        view.onSwitch = { switched.append($0) }
        let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -1, wheel2: 0, wheel3: 0)!
        wheel.flags = []; wheel.timestamp = 2_000_000_000
        view.scrollWheel(with: NSEvent(cgEvent: wheel)!)
        precondition(switched == [1], "ordinary scrolling in the strip switches without Command")
        // A strip that grows or moves under a still pointer can miss its exit
        // event. The pointer check ends the hover anyway.
        _ = NSApplication.shared
        let panel = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 620, height: 56), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        let watched = LaneScrollHostingView(rootView: AnyView(Color.clear))
        panel.contentView = watched
        var pointer = CGPoint(x: 120, y: 120)
        watched.pointerLocation = { pointer }
        var watchedHover: [Bool] = []
        watched.onHover = { watchedHover.append($0) }
        watched.mouseEntered(with: event(.mouseEntered))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: StripHoverCheck.interval * 2.5))
        precondition(watchedHover == [true] && watched.visibility.hovered, "a pointer still on the strip keeps it hovered")
        pointer = CGPoint(x: 900, y: 120)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: StripHoverCheck.interval * 2.5))
        precondition(watchedHover == [true, false] && !watched.visibility.hovered, "a missed exit still releases the strip and its keys")
        precondition(!StripHoverCheck.contains(nil, .zero), "a closed strip never counts as hovered")
        precondition(StripHoverCheck.contains(CGRect(x: 0, y: 0, width: 10, height: 10), CGPoint(x: 12, y: 5)), "the edge of a strip still counts as on it")
        print("PASS: native category-strip first click, active-app-independent tracking, hover enter/exit, full idle transparency, canceled fade, plain wheel switching, and release after a missed exit")
    }
}
