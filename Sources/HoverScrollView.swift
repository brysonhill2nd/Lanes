import SwiftUI
import AppKit

// Fade the SwiftUI drawing, not the panel or its native tracking area. The
// transparent strip remains a stable hover target and emits no idle pixels.
final class StripVisibility: ObservableObject {
    @Published private(set) var opacity = 1.0
    // Lowest idle opacity. Strips drawn over windows stay faintly visible.
    @Published var floor = 0.0
    var visible: Bool { opacity > 0 }
    private var fadeTimer: Timer?
    private var pending: DispatchWorkItem?
    private var started = false
    private(set) var hovered = false
    let idleDelay: TimeInterval
    let fadeDuration: TimeInterval
    init(idleDelay: TimeInterval = 1.5, fadeDuration: TimeInterval = 0.3) { self.idleDelay = idleDelay; self.fadeDuration = fadeDuration }
    func start() {
        guard !started else { return }; started = true
        scheduleFade()
    }
    func setHovered(_ value: Bool) {
        hovered = value; cancel()
        if value { opacity = 1 } else { scheduleFade() }
    }
    func cancel() { pending?.cancel(); pending = nil; fadeTimer?.invalidate(); fadeTimer = nil }
    private func scheduleFade() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hovered else { return }
            // Explicit opacity steps also complete for newly created panels,
            // without depending on SwiftUI's first display-link animation.
            let start = Date()
            self.fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] timer in
                guard let self, !self.hovered else { timer.invalidate(); return }
                let progress = self.fadeDuration > 0 ? Date().timeIntervalSince(start) / self.fadeDuration : 1
                self.opacity = max(0, 1 - progress)
                if progress >= 1 { self.opacity = 0; timer.invalidate(); self.fadeTimer = nil }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleDelay, execute: work)
    }
    deinit { pending?.cancel(); fadeTimer?.invalidate() }
}
struct FadingStripContent: View {
    @ObservedObject var visibility: StripVisibility
    let content: AnyView
    var body: some View {
        content.opacity(max(visibility.floor, visibility.opacity))
    }
}

final class LaneScrollHostingView: NSHostingView<AnyView> {
    var onSwitch: ((Int) -> Void)?
    var onHover: ((Bool) -> Void)?
    let visibility = StripVisibility()
    func setStripContent(_ content: AnyView) {
        rootView = AnyView(FadingStripContent(visibility: visibility, content: content))
        visibility.start()
    }
    override var isOpaque: Bool { false }
    private var hoverTracking: NSTrackingArea?
    private var accumulator = LaneScrollAccumulator()
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking); hoverTracking = tracking
    }
    override func mouseEntered(with event: NSEvent) { visibility.setHovered(true); onHover?(true) }
    override func mouseExited(with event: NSEvent) { visibility.setHovered(false); onHover?(false) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window != nil && newWindow == nil { visibility.cancel(); onHover?(false) }
        super.viewWillMove(toWindow: newWindow)
    }
    override func scrollWheel(with event: NSEvent) {
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        if let direction = accumulator.consume(delta: delta, precise: event.hasPreciseScrollingDeltas, time: event.timestamp, momentum: !event.momentumPhase.isEmpty) {
            onSwitch?(direction)
        }
    }
}
