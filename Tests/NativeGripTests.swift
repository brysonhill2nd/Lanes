import AppKit
import SwiftUI

@main struct NativeGripTests {
    @MainActor static func main() {
        let view = ResizeGripView(frame: CGRect(x: 0, y: 0, width: 12, height: 180))
        var phases: [ResizePhase] = []
        var deltas: [CGSize] = []
        view.onDrag = { delta, phase in phases.append(phase); deltas.append(delta) }
        func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 1,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        precondition(view.acceptsFirstMouse(for: nil), "edge dragging must work on the first click")
        precondition(view.hitTest(CGPoint(x: 6, y: 90)) === view, "the full edge grip must receive mouse input")
        view.mouseDown(with: mouse(.leftMouseDown, 300, 500))
        view.mouseDragged(with: mouse(.leftMouseDragged, 340, 475))
        // Relayout while dragging must not change the origin of measured deltas.
        view.frame.origin = CGPoint(x: 50, y: 20)
        view.mouseDragged(with: mouse(.leftMouseDragged, 360, 455))
        view.mouseUp(with: mouse(.leftMouseUp, 370, 445))
        precondition(phases.count == 4 && phases[0] == .began && phases[1] == .changed && phases[3] == .ended)
        precondition(deltas == [.zero, CGSize(width: 40, height: 25), CGSize(width: 60, height: 45), CGSize(width: 70, height: 55)], "resize deltas use stable window coordinates and screen-down Y")
        view.mouseDragged(with: mouse(.leftMouseDragged, 999, 999))
        precondition(phases.count == 4, "released grip must stop resizing")
        view.mouseDown(with: mouse(.leftMouseDown, 10, 10))
        view.mouseUp(with: mouse(.leftMouseUp, 5, 20))
        precondition(deltas.last == CGSize(width: -5, height: -10), "a second drag resets its origin")
        print("PASS: native grip hit area, first click, drag phases, stable deltas across relayout, release, and consecutive drags")
    }
}
