import SwiftUI
import AppKit

enum ResizePhase { case began, changed, ended }

// Native mouse tracking gives each grip its own hit area and resize cursor.
// Window coordinates stay stable even while SwiftUI moves the shared border.
struct NativeResizeGrip: NSViewRepresentable {
    let edge: ResizeEdge
    let onDrag: (CGSize, ResizePhase) -> Void
    func makeNSView(context: Context) -> ResizeGripView {
        let view = ResizeGripView(); view.edge = edge; view.onDrag = onDrag; return view
    }
    func updateNSView(_ view: ResizeGripView, context: Context) {
        view.edge = edge; view.onDrag = onDrag; view.window?.invalidateCursorRects(for: view)
    }
}
// Moves the strip panel that contains it. Screen coordinates, so the offset
// stays correct while the window itself moves under the cursor.
struct NativeMoveGrip: NSViewRepresentable {
    let onMove: (NSRect, ResizePhase) -> Void
    func makeNSView(context: Context) -> MoveGripView { let view = MoveGripView(); view.onMove = onMove; return view }
    func updateNSView(_ view: MoveGripView, context: Context) { view.onMove = onMove }
}
final class MoveGripView: NSView {
    var onMove: ((NSRect, ResizePhase) -> Void)?
    private var start: (mouse: NSPoint, origin: NSPoint)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        start = (NSEvent.mouseLocation, window.frame.origin)
        NSCursor.closedHand.push(); onMove?(window.frame, .began)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start, let window else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
        onMove?(window.frame, .changed)
    }
    override func mouseUp(with event: NSEvent) {
        guard start != nil, let window else { return }
        start = nil; NSCursor.pop()
        onMove?(window.frame, .ended)
    }
}
final class ResizeGripView: NSView {
    var edge: ResizeEdge = .right
    var onDrag: ((CGSize, ResizePhase) -> Void)?
    private var origin: CGPoint?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() {
        let cursor: NSCursor = edge == .top || edge == .bottom ? .resizeUpDown : edge == .bottomRight ? .crosshair : .resizeLeftRight
        addCursorRect(bounds, cursor: cursor)
    }
    override func mouseDown(with event: NSEvent) {
        origin = event.locationInWindow; onDrag?(.zero, .began)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let origin else { return }
        onDrag?(CGSize(width: event.locationInWindow.x - origin.x, height: origin.y - event.locationInWindow.y), .changed)
    }
    override func mouseUp(with event: NSEvent) {
        guard let origin else { return }
        onDrag?(CGSize(width: event.locationInWindow.x - origin.x, height: origin.y - event.locationInWindow.y), .ended)
        self.origin = nil
    }
}
