import AppKit

// macOS can refuse a background app's request to bring another app forward
// (it does for Dock apps since macOS 14). Lanes is a menu bar app, so the
// request normally works; if it is ever refused, Lanes falls back to the
// window server call that app switchers use, so strips keep switching apps.
enum FrontProcess {
    private typealias SetFront = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
    private typealias GetPSN = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32
    private static let anywhere = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
    private static let setFront: SetFront? = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        .flatMap { dlsym($0, "_SLPSSetFrontProcessWithOptions") }.map { unsafeBitCast($0, to: SetFront.self) }
    private static let getWindow: GetWindow? = dlsym(anywhere, "_AXUIElementGetWindow").map { unsafeBitCast($0, to: GetWindow.self) }
    private static let getPSN: GetPSN? = dlsym(anywhere, "GetProcessForPID").map { unsafeBitCast($0, to: GetPSN.self) }
    static func bring(pid: pid_t, window: AXUIElement) -> Bool {
        guard let setFront, let getPSN else { return false }
        var psn = ProcessSerialNumber()
        guard getPSN(pid, &psn) == 0 else { return false }
        var windowID: UInt32 = 0
        if let getWindow { _ = getWindow(window, &windowID) }
        return setFront(&psn, windowID, 0x200) == 0  // 0x200: user generated
    }
}
import ApplicationServices
import Combine
import ServiceManagement

struct ManagedWindow: Identifiable {
    let id: String
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String
    let appName: String
    let title: String
    let icon: NSImage?
    var frame: CGRect
    var minimized: Bool
    var lane: Lane
}
struct RunningAppSummary: Identifiable {
    let pid: pid_t
    let name: String
    let bundleID: String
    let icon: NSImage?
    let lane: Lane
    var id: pid_t { pid }
}
struct SavedWindow {
    let element: AXUIElement
    let frame: CGRect
    let minimized: Bool
}

func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value
}
func axBool(_ element: AXUIElement, _ attribute: String) -> Bool { (axValue(element, attribute) as? Bool) ?? false }
func axFrame(_ element: AXUIElement) -> CGRect? {
    guard let position = axValue(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
          let size = axValue(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero, dimensions = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
    return CGRect(origin: point, size: dimensions)
}

@MainActor final class WindowManager: ObservableObject {
    @Published var settings: Settings
    @Published var windows: [ManagedWindow] = []
    @Published var runningApps: [RunningAppSummary] = []
    @Published var selectedLane: Lane = .terminal
    @Published var gridSelectionActive = false
    @Published var renameTarget: Lane?
    @Published var renameWindowID: String?
    @Published var visibleSlotIDs: [Lane: [String]] = [:]
    @Published var activeSlot: [Lane: Int] = [:]
    @Published var showAccessHelp = false
    // An Expand-on-hover strip currently shown at its detailed size.
    @Published var expandedStrip: Lane?
    private var collapseStrip: DispatchWorkItem?
    @Published var hoveredLane: Lane? { didSet { if hoveredLane != oldValue { onHoveredLaneChanged?() } } }
    @Published var pages: [Lane: Int] = [:]
    @Published var trusted = AXIsProcessTrusted() { didSet { if oldValue != trusted { onTrustChanged?() } } }
    @Published var status = "Your desktop, with a place for everything."
    @Published var canUndo = false
    @Published var screens: [NSScreen] = NSScreen.screens
    @Published var selectedTemplateChanged = false
    @Published var busy = false
    @Published var layoutHistory: [Settings] = []
    @Published var editorPreview: [String: ZoneRect]?
    // The grid in the Lanes window is a draft: edits there change nothing on the
    // screen until Apply. `grid` is what the editor shows; `settings` is what the
    // screen uses. While a draft edit runs, window moves, strip updates and saving
    // are switched off.
    @Published var gridDraft: Settings?
    private var editingDraft = false
    var grid: Settings { editingDraft ? settings : (gridDraft ?? settings) }
    var gridLanes: [Lane] { grid.enabledLanes }
    private(set) var snapshot: [String: SavedWindow] = [:]
    private var overrides: [String: Lane] = [:]
    @Published var activeIDs: [Lane: String] = [:]
    private var managedIDs: Set<String> = []
    // The strip being dragged keeps its panel frame until the drag ends.
    var draggingStrip: Lane?
    // From the last refresh: windows in each app's own (front-to-back) order,
    // and the window server's on-screen stack, front first.
    private var discoveryOrder: [SeenWindow] = []
    // Windows whose category is shelved or hidden. Lanes neither lists nor tiles them.
    private(set) var outsideGrid: [ManagedWindow] = []
    // Windows you placed yourself. Lanes never second-guesses them from where they sit.
    var userPlaced: Set<String> { Set(settings.placedWindows) }
    func markPlaced(_ id: String) {
        guard !settings.placedWindows.contains(id) else { return }
        settings.placedWindows.append(id)
        if settings.placedWindows.count > 400 { settings.placedWindows.removeFirst(settings.placedWindows.count - 400) }
    }
    private var onScreenStack: [(pid: Int32, frame: CGRect)] = []
    private var timer: Timer?
    // One window-created watcher per running app, for centering new windows.
    private var windowWatchers: [pid_t: AXObserver] = [:]
    private var lastSignature = ""
    private var stripSignature = ""
    private var tick = 0
    private var lastRecordedTrust: Bool?
    private var observedMinimumSizes: [Lane: CGSize] = [:]
    private var hiddenAppSnapshot: [pid_t: Bool] = [:]
    private var lastWorkingPID: pid_t?
    private var activationObserver: NSObjectProtocol?
    var onGridSelection: (() -> Void)?
    var onHoveredLaneChanged: (() -> Void)?
    var onTrustChanged: (() -> Void)?
    var onLaneControls: (() -> Void)?
    var onHideLaneControls: (() -> Void)?
    var onSwitcher: (() -> Void)?
    var onHide: (() -> Void)?
    var onShow: (() -> Void)?
    // The Lanes window never closes by itself. An action started in it keeps it in
    // front once windows are arranged; from a shortcut elsewhere, focus returns to
    // the window you were working in.
    var isBoardVisible: (() -> Bool)?
    var onKeepBoard: (() -> Void)?
    var startedInBoard: Bool { NSApp?.isActive == true && (isBoardVisible?() ?? false) }
    var onOverlay: (([(Lane, CGRect)]) -> Void)?
    private let settingsURL: URL

    init(settingsFile: URL? = nil, startPolling: Bool = true) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lanes")
        settingsURL = settingsFile ?? folder.appendingPathComponent("settings.json")
        // A new install starts from the recommended setup; test fixtures start from plain defaults.
        let saved = (try? Data(contentsOf: settingsURL)).flatMap { try? JSONDecoder().decode(Settings.self, from: $0) }
        settings = saved ?? (settingsFile == nil ? .firstRun : Settings())
        let freshInstall = saved == nil && settingsFile == nil
        overrides = settings.windowCategories.compactMapValues(Lane.init(rawValue:))
        if startPolling {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, !self.busy else { return }
                // Read the previous app's exact focused window when Lanes takes
                // focus, even if the user switched windows within that app.
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier != getpid() { self.lastWorkingPID = app.processIdentifier }
                self.rememberWorkingWindow()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screens = NSScreen.screens; self?.syncDisplayLayout(); self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.appLaunched(app) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.unwatch(app.processIdentifier) }
        }
        }
        if !enabledLanes.contains(selectedLane), let first = enabledLanes.first { selectedLane = first }
        refresh()
        if startPolling { syncDisplayLayout(fresh: freshInstall); rememberWorkingWindow(); updateNewWindowWatch() }
    }
    // New windows are handled the moment macOS reports them: centered, or, when
    // they open over a category's window, counted in that category.
    func updateNewWindowWatch() {
        guard trusted, settings.newWindowPlacement != .category else { for pid in Array(windowWatchers.keys) { unwatch(pid) }; return }
        for app in regularRunningApps() where windowWatchers[app.processIdentifier] == nil { watch(app.processIdentifier) }
    }
    private func watch(_ pid: pid_t) {
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, _, context in
            guard let context else { return }
            let manager = Unmanaged<WindowManager>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { manager.windowCreated(element) }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else { return }
        let app = AXUIElementCreateApplication(pid)
        guard AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, Unmanaged.passUnretained(self).toOpaque()) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        windowWatchers[pid] = observer
    }
    private func unwatch(_ pid: pid_t) {
        guard let observer = windowWatchers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
    // A freshly launched app may open its first window before it can be watched.
    private func appLaunched(_ app: NSRunningApplication) {
        guard trusted, settings.newWindowPlacement != .category, app.activationPolicy == .regular, app.processIdentifier != getpid() else { return }
        watch(app.processIdentifier)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let elements = axValue(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement] else { return }
            for element in elements { self.handleNewWindow(element) }
        }
    }
    func windowCreated(_ element: AXUIElement) {
        // Let the app finish positioning its window first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.handleNewWindow(element) }
    }
    private var centeredWindows: Set<String> = []
    private func handleNewWindow(_ element: AXUIElement) {
        guard trusted, settings.newWindowPlacement != .category, NSEvent.pressedMouseButtons == 0 else { return }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != getpid(),
              (axValue(element, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole,
              !axBool(element, "AXFullScreen"), !axBool(element, kAXMinimizedAttribute),
              let frame = axFrame(element), frame.width > 80, frame.height > 60,
              centeredWindows.insert("\(pid)-\(CFHash(element))").inserted else { return }
        // A new tab opens in its tab group's spot, beside the tab it hides.
        // Moving it would drag the whole group, so tabs stay where they are.
        let all = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let sameSpot = all.filter { item in
            guard (item[kCGWindowOwnerPID as String] as? Int) == Int(pid), (item[kCGWindowLayer as String] as? Int) == 0,
                  let b = item[kCGWindowBounds as String] as? [String: CGFloat], let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"] else { return false }
            return TabSwitch.sameSpot(CGRect(x: x, y: y, width: w, height: h), frame)
        }
        // Arc, Ghostty and others open a new window exactly over the current one:
        // it stays there and joins that window's category. Otherwise Center
        // mode moves it to the middle, where it belongs to no category.
        if sameSpot.count < 2 && settings.newWindowPlacement == .center {
            let target = NewWindowCenter.frame(for: frame.size, in: screenFrame, gap: settings.gap)
            if !TabSwitch.sameSpot(target, frame) { move(element, to: target) }
            return
        }
        refresh(silent: true)
        followLayout()
    }
    // Categories follow where windows are: a window that fills a category's
    // tile counts in that category, whichever app it belongs to, so its strip
    // appears and switching includes it. Floating windows are left alone.
    @discardableResult func followLayout() -> Int {
        guard trusted, !busy, draggingStrip == nil else { return 0 }
        let tiles = enabledLanes.flatMap { lane in
            Layout.tiles(in: laneFrame(lane), count: settings.capacity(lane), gap: settings.gap, lane: lane).enumerated().map { (lane: lane, tile: $0.element, index: $0.offset) }
        }
        var joined: [(id: String, lane: Lane, index: Int)] = []
        for window in windows + outsideGrid where !window.minimized && !userPlaced.contains(window.id) {
            guard let lane = TileMembership.category(of: window.frame, tiles: tiles.map { (lane: $0.lane, tile: $0.tile) }), lane != window.lane else { continue }
            let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
            let index = tiles.first { $0.lane == lane && $0.tile.contains(center) }?.index ?? 0
            overrides[window.id] = lane; settings.windowCategories[window.id] = lane.rawValue
            joined.append((window.id, lane, index))
        }
        guard !joined.isEmpty else { return 0 }
        save(); refresh(silent: true)
        for move in joined {
            guard let window = windows.first(where: { $0.id == move.id }) else { continue }
            if canUndo { capture(window); managedIDs.insert(window.id) }
            let slots = WindowSlots.normalized(visibleSlotIDs[move.lane] ?? [], ids: items(move.lane).map(\.id), capacity: settings.capacity(move.lane))
            visibleSlotIDs[move.lane] = WindowSlots.replacing(slots, with: window.id, at: move.index)
            activeIDs[move.lane] = window.id; activeSlot[move.lane] = move.index
        }
        status = joined.count == 1 ? "\(windows.first { $0.id == joined[0].id }.map(windowLabel) ?? "A window") now counts in \(name(joined[0].lane)), where it sits." : "\(joined.count) windows now count in the categories where they sit."
        onLaneControls?()
        return joined.count
    }
    var screen: NSScreen? { screens.first(where: { Self.displayID($0) == settings.screenID }) ?? screens.max(by: { $0.frame.width < $1.frame.width }) }
    static func displayID(_ screen: NSScreen) -> UInt32 { (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
    var screenFrame: CGRect {
        guard let screen else { return CGRect(x: 0, y: 0, width: 1920, height: 1080) }
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let rect = screen.visibleFrame
        return CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }
    var enabledLanes: [Lane] { settings.enabledLanes }
    var displayLabel: String {
        guard let screen else { return "No display" }
        return "\(screen.localizedName) · \(Int(screen.frame.width)) × \(Int(screen.frame.height))"
    }
    func save() {
        guard !editingDraft else { return }
        do {
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: settingsURL, options: .atomic)
        } catch { status = "Could not save preferences: \(error.localizedDescription)" }
    }
    func poll() {
        if !busy { rememberWorkingWindow() }
        let granted = AXIsProcessTrusted()
        if granted != trusted { trusted = granted; refresh(); if granted { adoptArrangement() }; updateNewWindowWatch() }
        tick += 1
        if !trusted { refresh(silent: true); return }
        if trusted && (settings.autoArrange || tick % 5 == 0) && !busy {
            let previous = windows
            refresh(silent: true)
            followLayout()
            let signature = windows.map { "\($0.id):\($0.lane.rawValue)" }.sorted().joined(separator: ",")
            // Strips appear and disappear as categories gain or lose a second window.
            if signature != stripSignature { stripSignature = signature; onLaneControls?() }
            if settings.autoArrange && signature != lastSignature {
                lastSignature = signature
                placeNewWindows(previous: previous)
            }
        }
    }
    func placeNewWindows(previous: [ManagedWindow] = []) {
        guard settings.autoArrange, canUndo, trusted, !busy else { return }
        busy = true
        defer { busy = false }
        let focused = focusedWindow()
        adoptTabSwitches(previous: previous)
        var count = 0
        for lane in enabledLanes {
            let all = items(lane)
            let oldSlots = visibleSlotIDs[lane] ?? []
            var slots = WindowSlots.normalized(oldSlots, ids: all.map(\.id), capacity: settings.capacity(lane))
            let newIDs = Set(all.filter { !managedIDs.contains($0.id) && !$0.minimized && NSRunningApplication(processIdentifier: $0.pid)?.isHidden != true }.map(\.id))
            if let focused, focused.lane == lane, newIDs.contains(focused.id) {
                slots = WindowSlots.replacing(slots, with: focused.id, at: activeSlot[lane] ?? 0)
                activeIDs[lane] = focused.id
            }
            visibleSlotIDs[lane] = slots
            let replacements = Set(slots.filter { !$0.isEmpty }).subtracting(oldSlots)
            let touched = newIDs.union(replacements)
            guard !touched.isEmpty else { continue }
            _ = apply(lane, raiseWindows: false, onlyIDs: touched)
            // Raising a window of the app you are typing in makes it the key
            // window and steals the keyboard. Only other apps' windows are raised.
            let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
            for id in replacements {
                if let window = all.first(where: { $0.id == id }), window.pid != frontmost { _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) }
            }
            count += newIDs.count
        }
        if count > 0 { status = "Placed \(count) new windows. Existing windows and category sizes stayed in place." }
        onLaneControls?()
    }
    // A tab switch hides one window and shows another in the same spot. The new
    // tab takes over the old one's category, slot and selection without moving,
    // so a different window is never pulled into that tile.
    private func adoptTabSwitches(previous: [ManagedWindow]) {
        let current = Set(windows.map(\.id))
        let vanished = previous.filter { !current.contains($0.id) && managedIDs.contains($0.id) }
        guard !vanished.isEmpty else { return }
        let appeared = windows.filter { !managedIDs.contains($0.id) && !$0.minimized }
        let swaps = TabSwitch.pairs(vanished: vanished.map { SeenWindow(id: $0.id, pid: $0.pid, frame: $0.frame) }, appeared: appeared.map { SeenWindow(id: $0.id, pid: $0.pid, frame: $0.frame) })
        var recategorized = false
        for (tab, old) in swaps {
            guard let oldWindow = vanished.first(where: { $0.id == old }), let index = windows.firstIndex(where: { $0.id == tab }) else { continue }
            let lane = oldWindow.lane
            if windows[index].lane != lane {
                overrides[tab] = lane; settings.windowCategories[tab] = lane.rawValue
                windows[index].lane = lane; recategorized = true
            }
            visibleSlotIDs[lane] = (visibleSlotIDs[lane] ?? []).map { $0 == old ? tab : $0 }
            if activeIDs[lane] == old { activeIDs[lane] = tab }
            capture(windows[index]); managedIDs.insert(tab)
        }
        if recategorized { save() }
    }
    // After Lanes restarts (an update, a crash), take over the windows that
    // already sit in their category's tiles without moving or raising anything,
    // so strips and automatic placement work without pressing Organize again.
    func adoptArrangement() {
        guard trusted, !canUndo, !busy, settings.showLaneControls || settings.autoArrange, !settings.customRects.isEmpty else { return }
        refresh(silent: true)
        followLayout()
        let order = StackOrder.positions(windows: discoveryOrder, onScreen: onScreenStack)
        var adopted = 0
        for lane in enabledLanes {
            let all = items(lane), capacity = settings.capacity(lane)
            let tiles = Layout.tiles(in: laneFrame(lane), count: capacity, gap: settings.gap, lane: lane)
            let pick = StackOrder.adoptedSlots(tiles: tiles, windows: all.filter { !$0.minimized }.map { SeenWindow(id: $0.id, pid: $0.pid, frame: $0.frame) }, order: order)
            guard !pick.adopted.isEmpty else { continue }
            for id in pick.adopted { if let window = all.first(where: { $0.id == id }) { capture(window); managedIDs.insert(id) } }
            visibleSlotIDs[lane] = WindowSlots.normalized(pick.slots, ids: all.map(\.id), capacity: capacity)
            if let front = pick.slots.first(where: { !$0.isEmpty }) { activeIDs[lane] = front; activeSlot[lane] = pick.slots.firstIndex(of: front) }
            adopted += pick.adopted.count
        }
        guard adopted > 0 else { return }
        status = "Picked up \(adopted) windows where they were. Organize re-arranges everything."
        onLaneControls?()
    }
    func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if trusted { refresh() }
        else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    func refresh(silent: Bool = false, restorePopulatedCategories: Bool = false) {
        // An edit works against a temporary copy of settings and window state.
        // Discovery belongs to the applied grid, so defer it until after Apply.
        guard !editingDraft else { return }
        refreshRunningApps()
        trusted = AXIsProcessTrusted()
        recordPermissionState()
        guard trusted else {
            windows = []
            if !silent { status = "\(runningApps.count) running apps found. Enable window control to see their windows." }
            return
        }
        let oldOrder = Dictionary(uniqueKeysWithValues: windows.enumerated().map { ($1.id, $0) })
        let onScreen = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        var visibleRects: [pid_t: [CGRect]] = [:]
        var stack: [(pid: Int32, frame: CGRect)] = []
        var outside: [ManagedWindow] = []
        for item in onScreen where (item[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = item[kCGWindowOwnerPID as String] as? Int,
                  let bounds = item[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"] else { continue }
            visibleRects[pid_t(pid), default: []].append(CGRect(x: x, y: y, width: w, height: h))
            stack.append((pid: Int32(pid), frame: CGRect(x: x, y: y, width: w, height: h)))
        }
        onScreenStack = stack
        var result: [ManagedWindow] = []
        var populated: Set<Lane> = []
        var seenWindowIDs: Set<String> = []
        for app in regularRunningApps() {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.2)
            guard let elements = axValue(appElement, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for element in elements {
                AXUIElementSetMessagingTimeout(element, 0.2)
                let rawTitle = (axValue(element, kAXTitleAttribute) as? String) ?? ""
                let subrole = axValue(element, kAXSubroleAttribute) as? String
                guard subrole == kAXStandardWindowSubrole || Classifier.isCompactPlayer(title: rawTitle) else { continue }
                guard !axBool(element, "AXFullScreen"), let frame = axFrame(element), frame.width > 80, frame.height > 60 else { continue }
                let id = "\(app.processIdentifier)-\(CFHash(element))"
                guard seenWindowIDs.insert(id).inserted else { continue }
                let minimized = axBool(element, kAXMinimizedAttribute)
                let known = managedIDs.contains(id)
                if !known {
                    guard minimized || app.isHidden || visibleRects[app.processIdentifier, default: []].contains(where: { abs($0.minX-frame.minX) < 8 && abs($0.minY-frame.minY) < 8 }) else { continue }
                }
                if settings.onlyTargetScreen && !known && !screenFrame.contains(CGPoint(x: frame.midX, y: frame.midY)) { continue }
                let bundle = app.bundleIdentifier ?? "pid.\(app.processIdentifier)"
                let appName = app.localizedName ?? "App"
                let title = (axValue(element, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 } ?? appName
                let lane = overrides[id] ?? Classifier.lane(bundleID: bundle, appName: appName, title: title, rules: settings.appRules)
                if restorePopulatedCategories && availableLanes.contains(lane) && !settings.shelvedLanes.contains(lane.rawValue) { populated.insert(lane) }
                else if !enabledLanes.contains(lane) {
                    // Its category is shelved or hidden: the window stays out of the grid.
                    outside.append(ManagedWindow(id: id, element: element, pid: app.processIdentifier, bundleID: bundle, appName: appName, title: title, icon: app.icon, frame: frame, minimized: minimized, lane: lane))
                    continue
                }
                result.append(ManagedWindow(id: id, element: element, pid: app.processIdentifier, bundleID: bundle, appName: appName, title: title, icon: app.icon, frame: frame, minimized: minimized, lane: lane))
            }
        }
        discoveryOrder = result.map { SeenWindow(id: $0.id, pid: $0.pid, frame: $0.frame) }
        result.sort {
            let categoryA = availableLanes.firstIndex(of: $0.lane) ?? Int.max, categoryB = availableLanes.firstIndex(of: $1.lane) ?? Int.max
            if categoryA != categoryB { return categoryA < categoryB }
            let saved = settings.windowOrder[$0.lane.rawValue] ?? []
            let a = saved.firstIndex(of: $0.id) ?? (saved.count + (oldOrder[$0.id] ?? 100000)), b = saved.firstIndex(of: $1.id) ?? (saved.count + (oldOrder[$1.id] ?? 100000))
            if a != b { return a < b }
            return ($0.appName, $0.title, $0.id) < ($1.appName, $1.title, $1.id)
        }
        if restorePopulatedCategories && !populated.isEmpty {
            settings.hiddenLanes = availableLanes.filter { !populated.contains($0) }.map(\.rawValue)
            settings.showMediaShelf = populated.contains(.media)
        }
        windows = result
        outsideGrid = outside
        for lane in enabledLanes { pages[lane] = min(pages[lane] ?? 0, pageCount(lane) - 1) }
        if !silent { status = "\(windows.count) windows found. Assign them, then arrange your desktop." }
    }
    // Windows outside every category are left alone, except that Organize
    // moves any covering a category to the middle so the grid stays clear.
    private func centerStrays() -> Int {
        let regions = enabledLanes.map(rawLaneFrame)
        var moved = 0
        for window in outsideGrid where !window.minimized && NSRunningApplication(processIdentifier: window.pid)?.isHidden != true {
            guard StrayWindow.coversGrid(window.frame, regions: regions) else { continue }
            let target = NewWindowCenter.frame(for: window.frame.size, in: screenFrame, gap: settings.gap)
            if !TabSwitch.sameSpot(target, window.frame), movePreservingOriginal(window, to: target) { moved += 1 }
        }
        return moved
    }
    func regularRunningApps() -> [NSRunningApplication] {
        var seen: Set<pid_t> = []
        return NSWorkspace.shared.runningApplications.filter { app in
            app.processIdentifier > 0 && app.processIdentifier != getpid() && app.activationPolicy == .regular && !app.isTerminated && seen.insert(app.processIdentifier).inserted
        }
    }
    func refreshRunningApps() {
        runningApps = regularRunningApps().map { app in
            let name = app.localizedName ?? "App"
            let lane = Classifier.lane(bundleID: app.bundleIdentifier ?? "", appName: name, title: "", rules: settings.appRules)
            return RunningAppSummary(pid: app.processIdentifier, name: name, bundleID: app.bundleIdentifier ?? "pid.\(app.processIdentifier)", icon: app.icon, lane: lane)
        }.sorted { ($0.name, $0.pid) < ($1.name, $1.pid) }
    }
    func apps(_ lane: Lane) -> [RunningAppSummary] { runningApps.filter { $0.lane == lane } }
    func discoveryCount(_ lane: Lane) -> String { trusted ? "\(items(lane).count)" : "\(apps(lane).count) apps" }
    // The window goes back to its app's usual category.
    func clearWindowCategory(_ window: ManagedWindow) {
        overrides.removeValue(forKey: window.id); settings.windowCategories.removeValue(forKey: window.id)
        markPlaced(window.id)
        save(); refresh(silent: true)
        if let back = windows.first(where: { $0.id == window.id }), trusted && canUndo && !busy { reveal(back) }
        onLaneControls?()
        status = "\(windowLabel(window)) is back with the rest of \(window.appName)."
    }
    func resetAppRule(_ app: RunningAppSummary) {
        settings.appRules.removeValue(forKey: app.bundleID); save(); refresh(silent: true)
        for window in windows where window.bundleID == app.bundleID { markPlaced(window.id) }
        for lane in Set(windows.filter { $0.bundleID == app.bundleID }.map(\.lane)) {
            let ids = Set(items(lane).filter { $0.bundleID == app.bundleID }.map(\.id))
            if trusted && canUndo && !busy { _ = apply(lane, raiseWindows: false, onlyIDs: ids) }
        }
        onLaneControls?()
        status = "\(app.name) uses its automatic category again."
    }
    // Every window of the app goes to the category now, without coming forward.
    func assignApp(_ app: RunningAppSummary, to lane: Lane) {
        settings.appRules[app.bundleID] = lane.rawValue
        // A rule for the whole app replaces one-off window choices for that app.
        for window in windows + outsideGrid where window.bundleID == app.bundleID {
            overrides.removeValue(forKey: window.id); settings.windowCategories.removeValue(forKey: window.id); markPlaced(window.id)
        }
        save(); refresh(silent: true)
        let ids = Set(items(lane).filter { $0.bundleID == app.bundleID }.map(\.id))
        if trusted && canUndo && !busy && !ids.isEmpty { _ = apply(lane, raiseWindows: false, onlyIDs: ids) }
        onLaneControls?()
        status = "\(app.name) now goes to \(name(lane))."; selectedTemplateChanged = true
    }
    func activateApp(_ app: RunningAppSummary) { NSRunningApplication(processIdentifier: app.pid)?.activate() }
    func items(_ lane: Lane) -> [ManagedWindow] { windows.filter { $0.lane == lane } }
    func pageCount(_ lane: Lane) -> Int { Layout.pageCount(total: items(lane).count, capacity: settings.capacity(lane)) }
    func visibleItems(_ lane: Lane) -> [ManagedWindow] {
        let items = items(lane)
        let ids = slotIDs(lane)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }
    func slotIDs(_ lane: Lane) -> [String] { WindowSlots.normalized(visibleSlotIDs[lane] ?? [], ids: items(lane).map(\.id), capacity: settings.capacity(lane)) }
    func rawLaneFrame(_ lane: Lane) -> CGRect { Layout.frame(unit: settings.unitRect(for: lane), in: screenFrame, gap: settings.gap) }
    func laneFrame(_ lane: Lane) -> CGRect {
        var frame = rawLaneFrame(lane)
        if settings.stripReservesSpace { let inset = stripMetrics(lane).reservedHeight; frame.origin.y += inset; frame.size.height = max(80, frame.height - inset) }
        return frame
    }
    func stripMetrics(_ lane: Lane) -> WindowStripMetrics {
        WindowStripMetrics.measure(style: settings.stripStyle(lane), count: items(lane).count, scale: settings.windowStripScale, availableWidth: rawLaneFrame(lane).width, slots: settings.capacity(lane))
    }
    // Top-left screen coordinates. Above the windows: the reserved band's left
    // edge. On the windows: centered on the region's top edge, or where it was dragged.
    func stripFrame(_ lane: Lane) -> CGRect {
        let region = rawLaneFrame(lane), idle = stripMetrics(lane), shown = displayedStripMetrics(lane)
        let restSize = CGSize(width: idle.width, height: idle.height)
        let rest = settings.stripPlacement == .onWindows
            ? StripPlacementGeometry.frame(size: restSize, region: region, bounds: screenFrame, saved: settings.stripPositions[lane.rawValue])
            : CGRect(origin: region.origin, size: restSize)
        guard shown.width != idle.width || shown.height != idle.height else { return rest }
        return StripPlacementGeometry.grown(rest: rest, size: CGSize(width: shown.width, height: shown.height), bounds: screenFrame)
    }
    func moveStrip(_ lane: Lane, to frame: CGRect) {
        // Save where the resting strip sits; an expanded strip shares its left edge.
        let idle = stripMetrics(lane)
        let rest = CGRect(x: frame.minX, y: frame.minY, width: idle.width, height: idle.height)
        settings.stripPositions[lane.rawValue] = StripPlacementGeometry.position(of: rest, in: rawLaneFrame(lane))
        save(); onLaneControls?()
    }
    func resetStripPosition(_ lane: Lane? = nil) {
        if let lane { settings.stripPositions.removeValue(forKey: lane.rawValue) } else { settings.stripPositions.removeAll() }
        save(); onLaneControls?()
        status = lane.map { "\(name($0)) strip moved back to the top edge." } ?? "Strips moved back to the top edge of each category."
    }
    func setStripPlacement(_ placement: StripPlacement) {
        settings.stripPlacement = placement
        stripAppearanceChanged()
        status = placement == .onWindows ? "Strips sit on the windows. Windows use the full height of each category." : "Strips sit in a band above each category."
    }
    // The panel's size right now. Layout and reserved space always use the
    // idle size, so hovering never moves a window.
    func displayedStripMetrics(_ lane: Lane) -> WindowStripMetrics {
        guard settings.stripStyle(lane) == .expanding, expandedStrip == lane else { return stripMetrics(lane) }
        return WindowStripMetrics.measure(style: .detailed, count: items(lane).count, scale: settings.windowStripScale, availableWidth: rawLaneFrame(lane).width, slots: settings.capacity(lane))
    }
    // Grows at once; shrinks a moment after the mouse leaves, so crossing the
    // edge of the growing strip cannot make it flicker.
    func stripHovered(_ lane: Lane, _ hovering: Bool) {
        collapseStrip?.cancel(); collapseStrip = nil
        if hovering {
            guard settings.stripStyle(lane) == .expanding, expandedStrip != lane else { return }
            expandedStrip = lane; onLaneControls?()
            return
        }
        guard expandedStrip == lane else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.expandedStrip == lane, self.hoveredLane != lane else { return }
            self.expandedStrip = nil; self.onLaneControls?()
        }
        collapseStrip = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    func stripAppearanceChanged(retile: Bool = true) {
        save()
        if retile && trusted && canUndo && !busy {
            for lane in enabledLanes { _ = apply(lane, raiseWindows: false) }
        }
        onLaneControls?()
        status = "Window strip appearance saved."
    }
    func activeWindow(_ lane: Lane) -> ManagedWindow? {
        let slots = slotIDs(lane), index = activeSlot[lane] ?? 0
        if slots.indices.contains(index), let window = items(lane).first(where: { $0.id == slots[index] }) { return window }
        return items(lane).first(where: { $0.id == activeIDs[lane] }) ?? visibleItems(lane).first
    }
    func windowCounter(_ lane: Lane) -> String {
        let all = items(lane)
        guard let window = activeWindow(lane), let index = all.firstIndex(where: { $0.id == window.id }) else { return "0/0" }
        return "\(index + 1)/\(all.count)"
    }
    func capture(_ window: ManagedWindow) {
        if hiddenAppSnapshot[window.pid] == nil { hiddenAppSnapshot[window.pid] = NSRunningApplication(processIdentifier: window.pid)?.isHidden ?? false }
        if snapshot[window.id] == nil {
            // Discovery already read the original frame. Preserve it even if a
            // fresh AX read temporarily fails immediately before moving it.
            let frame = axFrame(window.element) ?? window.frame
            let minimized = (axValue(window.element, kAXMinimizedAttribute) as? Bool) ?? window.minimized
            snapshot[window.id] = SavedWindow(element: window.element, frame: frame, minimized: minimized)
            canUndo = true
        }
    }
    @discardableResult func movePreservingOriginal(_ window: ManagedWindow, to frame: CGRect) -> Bool {
        capture(window)
        return move(window.element, to: frame)
    }
    @discardableResult func move(_ element: AXUIElement, to frame: CGRect) -> Bool {
        var position = frame.origin, size = frame.size
        guard let p = AXValueCreate(.cgPoint, &position), let s = AXValueCreate(.cgSize, &size) else { return false }
        // Two passes accommodate windows that clamp their origin when resizing.
        _ = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, s)
        let positionResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, p)
        _ = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, s)
        _ = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, p)
        guard positionResult == .success, let actual = axFrame(element) else { return false }
        // A fixed-size window is allowed if it fits inside the requested tile.
        let fits = actual.width <= frame.width + 12 && actual.height <= frame.height + 12 && abs(actual.minX-frame.minX) < 12 && abs(actual.minY-frame.minY) < 12
        return fits
    }
    func autoOrganize(hideBoard: Bool = true, forceAutoLayout: Bool = false) {
        guard !busy, !editingDraft else { return }
        guard trusted else { status = "Enable window control to arrange your apps."; return }
        let stay = startedInBoard
        let working = rememberWorkingWindow()
        guard commitPendingGrid() else { return }
        let previousSelections = Array(activeIDs.values)
        refresh(silent: true, restorePopulatedCategories: forceAutoLayout || !settings.useCustomGrid)
        guard trusted else { status = "macOS has not recognized window access for this Lanes build. Open Access help to repair its permission entry."; return }
        guard !windows.isEmpty else { status = "No movable windows found on this display. Check the display selector or turn off display filtering."; return }
        let workingWindow = working.flatMap { id in windows.first { $0.id == id } }
        for id in previousSelections {
            if let window = windows.first(where: { $0.id == id }) { activeIDs[window.lane] = id }
        }
        if let workingWindow { activeIDs[workingWindow.lane] = workingWindow.id }
        let order: [Lane] = [.terminal, .simulator, .browser, .desktop, .preview] + enabledLanes.filter(\.isCustom) + [.messaging, .media]
        let populated = order.filter { !items($0).isEmpty }
        for lane in populated {
            let saved = WindowSlots.normalized(visibleSlotIDs[lane] ?? [], ids: items(lane).map(\.id), capacity: settings.capacity(lane))
            visibleSlotIDs[lane] = activeIDs[lane].map { WindowSlots.replacing(saved, with: $0, at: activeSlot[lane] ?? 0) } ?? saved
        }
        if settings.useCustomGrid && !forceAutoLayout {
            for lane in enabledLanes { pages[lane] = 0 }
            arrange(hideBoard: hideBoard)
            if stay { onKeepBoard?() } else if let workingWindow { focus(workingWindow, hideBoard: false) }
            status = "Organized into your custom grid. Your category sizes and window strip styles are kept."
            return
        }
        observedMinimumSizes = [:]
        let plan = AutoSorter.plan(items: populated.map { AutoSortItem(lane: $0, count: items($0).count, isFocused: $0 == workingWindow?.lane, stripInset: settings.stripReservesSpace ? stripMetrics($0).reservedHeight : 0) }, screen: screenFrame, gap: settings.gap)
        rememberLayout(); settings.customRects = plan.rects; settings.useCustomGrid = false
        for (lane, capacity) in plan.capacities { settings.capacities[lane] = capacity; if let category = Lane(rawValue: lane) { pages[category] = 0 } }
        save(); refreshRunningApps(); arrange(hideBoard: hideBoard)
        // If an app clamps its size, give the measured minimum more weight and
        // choose the grid again rather than leaving an oversized window overlapping.
        if !observedMinimumSizes.isEmpty {
            let adjusted = AutoSorter.plan(items: populated.map { AutoSortItem(lane: $0, count: items($0).count, requiredSize: observedMinimumSizes[$0], isFocused: $0 == workingWindow?.lane, stripInset: settings.stripReservesSpace ? stripMetrics($0).reservedHeight : 0) }, screen: screenFrame, gap: settings.gap)
            settings.customRects = adjusted.rects
            for (id, capacity) in adjusted.capacities { settings.capacities[id] = capacity }
            save(); arrange(hideBoard: hideBoard)
        }
        if stay { onKeepBoard?() } else if let workingWindow { focus(workingWindow, hideBoard: false) }
        status = "Auto-sort · " + status + " Hover a category strip to scroll, use Left/Right, or select with 1–9 / 0."
    }
    // A preset shown on the grid in the Lanes window without touching the screen.
    // Apply uses it; Cancel or choosing another preset leaves everything as it was.
    struct PresetPreview: Equatable {
        let name: String
        let lanes: [Lane]
        let rects: [String: ZoneRect]
        let savedID: String?
        let shape: PresetShape?
    }
    @Published var presetPreview: PresetPreview?
    func previewPreset(_ shape: PresetShape) {
        let lanes = gridLanes
        let counts = Dictionary(uniqueKeysWithValues: lanes.map { ($0, items($0).count) })
        let main = lanes.contains(selectedLane) ? selectedLane : lanes.first ?? .terminal
        presetPreview = PresetPreview(name: shape.title, lanes: lanes, rects: shape.rects(lanes: lanes, main: main, windows: counts), savedID: nil, shape: shape)
    }
    func previewSavedLayout(_ layout: SavedGridLayout) {
        presetPreview = PresetPreview(name: layout.name, lanes: layout.lanes.compactMap(Lane.init(rawValue:)), rects: layout.rects, savedID: layout.id, shape: nil)
    }
    func applyPresetPreview() {
        guard presetPreview != nil, commitPendingGrid() else { return }
        if trusted { arrange(hideBoard: false) } else { onLaneControls?() }
    }
    // Every Apply/Organize entry point commits the same visible grid first.
    // Merely previewing a preset retains the draft underneath it for Cancel.
    @discardableResult func commitPendingGrid() -> Bool {
        let preview = presetPreview
        if let preview {
            guard GridGeometry.valid(preview.rects, lanes: preview.lanes) else {
                status = "This preset does not fit your categories."; return false
            }
            if let id = preview.savedID, !settings.savedLayouts.contains(where: { $0.id == id }) {
                status = "This preset is no longer available."; return false
            }
        }
        commitGridDraft()
        guard let preview else { return true }
        presetPreview = nil
        if let id = preview.savedID, let layout = settings.savedLayouts.first(where: { $0.id == id }) {
            loadGridLayout(layout)
        } else {
            settings.previousLayout = currentGridLayout(name: "Previous layout")
            let before = layoutRects()
            rememberLayout(); settings.customRects = preview.rects
            recenterMovedStrips(changedFrom: before)
            layoutChanged("\(preview.name) applied.")
        }
        return true
    }
    // The tour of the Lanes window: shown once on first launch, and again on request.
    @Published var tourStep: Int?
    private(set) var tourSteps: [TourStep] = []
    func startTour() {
        tourSteps = TourGuide.steps(trusted: trusted)
        tourStep = 0
    }
    func endTour() {
        tourStep = nil
        settings.hasSeenTour = true
        save()
    }
    // Open at login uses macOS's own login items (System Settings › General › Login Items).
    var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            status = on ? "Lanes opens when you log in." : "Lanes no longer opens at login."
        } catch {
            status = "macOS did not change the login item: \(error.localizedDescription)"
        }
        objectWillChange.send()
    }
    func recordPermissionState() {
        guard Bundle.main.bundleIdentifier == "com.bryson.lanes" else { return }
        guard lastRecordedTrust != trusted else { return }
        lastRecordedTrust = trusted
        let state: [String: Any] = ["trusted": trusted, "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "test", "executable": Bundle.main.executableURL?.path ?? "", "checkedAt": ISO8601DateFormatter().string(from: Date())]
        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: settingsURL.deletingLastPathComponent().appendingPathComponent("window-access-state.json"), options: .atomic)
    }
    func arrange(hideBoard: Bool = true) {
        guard !editingDraft else { return }
        guard trusted else { status = "Enable window control to arrange your apps."; return }
        guard commitPendingGrid() else { return }
        let stay = startedInBoard
        busy = true
        refresh(silent: true)
        if windows.isEmpty { status = "No movable windows on this desktop. Open some apps, then refresh."; busy = false; return }
        var constrained = 0, failed = 0
        for lane in enabledLanes {
            let outcome = apply(lane)
            constrained += outcome.constrained; failed += outcome.failed
        }
        let cleared = centerStrays()
        selectedTemplateChanged = false
        lastSignature = windows.map { "\($0.id):\($0.lane.rawValue)" }.sorted().joined(separator: ",")
        status = "Desktop arranged · \(windows.count) windows in \(enabledLanes.count) lanes."
        if cleared > 0 { status += " \(cleared) windows without a category moved to the middle." }
        if constrained > 0 { status += " \(constrained) tiles exceed app minimum sizes; use fewer tiles or widen a lane." }
        if failed > 0 { status += " \(failed) windows could not be positioned." }
        for lane in enabledLanes {
            for window in visibleItems(lane) {
                NSRunningApplication(processIdentifier: window.pid)?.activate()
                _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
            }
        }
        busy = false
        onLaneControls?()
        if stay { onKeepBoard?() }
    }
    func apply(_ lane: Lane, presentationOnly: Bool = false, raiseWindows: Bool = true, onlyIDs: Set<String>? = nil) -> (constrained: Int, failed: Int) {
        guard !editingDraft else { return (0, 0) }
        let all = items(lane), visible = visibleItems(lane)
        let slots = slotIDs(lane)
        if visibleSlotIDs[lane] != slots { visibleSlotIDs[lane] = slots }
        let ids = Set(visible.map(\.id))
        let stack = Layout.stack(ids: all.map(\.id), foreground: slots, in: laneFrame(lane), gap: settings.gap, lane: lane, presentationOnly: presentationOnly, onlyIDs: onlyIDs, slotCount: settings.capacity(lane))
        if !ids.contains(activeIDs[lane] ?? "") { activeIDs[lane] = visible.first?.id }
        var constrained = 0, failed = 0
        // Keep every discovered window open. Queue members share a tile behind
        // its selected window instead of disappearing into the Dock.
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        var updated: [String: ManagedWindow] = [:]
        for id in stack.raiseOrder {
            guard let window = byID[id], let frame = stack.frames[id] else { continue }
            capture(window); managedIDs.insert(window.id)
            if window.minimized && AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) != .success { failed += 1 }
            NSRunningApplication(processIdentifier: window.pid)?.unhide()
            let alreadySized = abs(window.frame.minX - frame.minX) < 2 && abs(window.frame.minY - frame.minY) < 2 && abs(window.frame.width - frame.width) < 2 && abs(window.frame.height - frame.height) < 2
            let positioned = alreadySized || move(window.element, to: frame)
            if !positioned {
                constrained += 1
                if let actual = axFrame(window.element), actual.width > frame.width + 12 || actual.height > frame.height + 12 {
                    let previous = observedMinimumSizes[lane] ?? AutoSorter.minimumSize(lane)
                    observedMinimumSizes[lane] = CGSize(width: max(previous.width, actual.width > frame.width + 12 ? actual.width : previous.width),
                        height: max(previous.height, actual.height > frame.height + 12 ? actual.height : previous.height))
                }
            }
            if positioned { var copy = window; copy.frame = frame; copy.minimized = false; updated[id] = copy }
            // Background windows are positioned without raising them. Switching
            // touches only the new foreground page; focus raises its chosen window.
            if raiseWindows && !presentationOnly && ids.contains(id) && AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) != .success { failed += 1 }
        }
        if !updated.isEmpty { windows = windows.map { updated[$0.id] ?? $0 } }
        return (constrained, failed)
    }
    func cycle(_ lane: Lane, delta: Int = 1) {
        cycleWindow(lane, delta: delta)
    }
    // Match the exact focused AX window, so two windows from the same browser
    // can be cycled or moved separately. Never guess from an app name.
    func focusedWindow() -> ManagedWindow? {
        guard trusted, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = axValue(element, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return windows.first { $0.pid == app.processIdentifier && CFEqual($0.element, focused) }
    }
    @discardableResult func rememberWorkingWindow() -> String? {
        guard trusted, !busy else { return nil }
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != getpid(), frontmost.activationPolicy == .regular {
            lastWorkingPID = frontmost.processIdentifier
        }
        guard let pid = lastWorkingPID else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let focused = axValue(app, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID(),
              let window = windows.first(where: { $0.pid == pid && CFEqual($0.element, focused) }) else { return nil }
        activeIDs[window.lane] = window.id
        if hoveredLane != window.lane, let slot = slotIDs(window.lane).firstIndex(of: window.id) { activeSlot[window.lane] = slot }
        return window.id
    }
    func cycleWindow(_ lane: Lane, delta: Int = 1) {
        guard !settings.hiddenLanes.contains(lane.rawValue) else { status = "Restore \(name(lane)) in Preferences to use its shortcut."; return }
        if lane == .media && !settings.showMediaShelf { restoreCategory(.media); arrange(hideBoard: false) }
        if items(lane).isEmpty { refresh(silent: true) }
        let all = items(lane)
        guard trusted, !all.isEmpty else {
            status = trusted ? "No windows in \(name(lane))." : "Enable window control to use window shortcuts."
            return
        }
        if hoveredLane != lane, let focused = focusedWindow(), focused.lane == lane, let slot = slotIDs(lane).firstIndex(of: focused.id) { activeSlot[lane] = slot }
        guard let nextID = WindowSlots.nextID(ids: all.map(\.id), slots: slotIDs(lane), slot: activeSlot[lane] ?? 0, delta: delta), let next = all.first(where: { $0.id == nextID }) else { return }
        reveal(next)
        status = "\(name(lane)) · \(windowCounter(lane)) · \(windowLabel(next))"
    }
    func cycleFocused(delta: Int = 1) {
        refresh(silent: true)
        guard let window = focusedWindow() else {
            status = "Focus an app window, then cycle its category."
            return
        }
        cycleWindow(window.lane, delta: delta)
    }
    func sendFocused(to lane: Lane) {
        guard !settings.hiddenLanes.contains(lane.rawValue) else { status = "Restore \(name(lane)) in Preferences before sending windows there."; return }
        refresh(silent: true)
        guard let window = focusedWindow() else {
            status = "Focus an app window, then use the send-to-lane shortcut."
            return
        }
        let needsReflow = lane == .media && !settings.showMediaShelf
        capture(window)
        assign(window, to: lane)
        if needsReflow { arrange(hideBoard: false) }
        guard let reassigned = windows.first(where: { $0.id == window.id }) else { return }
        reveal(reassigned)
        status = "\(window.appName) moved and resized into \(name(lane))."
    }
    func adjustFocused(dx: CGFloat, dy: CGFloat, resize: Bool) {
        refresh(silent: true)
        guard let window = focusedWindow(), let frame = axFrame(window.element) else {
            status = "Focus an app window to move or resize it."
            return
        }
        capture(window)
        let adjusted = Layout.adjust(frame: frame, bounds: laneFrame(window.lane), dx: dx, dy: dy, resize: resize)
        if adjusted == frame { status = "At the lane boundary. Resize the window first to make room."; return }
        let moved = move(window.element, to: adjusted)
        status = moved ? "\(window.appName) \(resize ? "resized" : "moved") within \(name(window.lane))." : "This app enforces a minimum window size or prevents resizing."
        focus(window)
    }
    func reveal(_ window: ManagedWindow) {
        guard !editingDraft else { return }
        selectedLane = window.lane
        if hoveredLane != window.lane, let focused = focusedWindow(), focused.lane == window.lane, let slot = slotIDs(window.lane).firstIndex(of: focused.id) { activeSlot[window.lane] = slot }
        let oldSlots = slotIDs(window.lane)
        visibleSlotIDs[window.lane] = WindowSlots.replacing(oldSlots, with: window.id, at: activeSlot[window.lane] ?? 0)
        _ = apply(window.lane, presentationOnly: true, onlyIDs: [window.id])
        focus(window)
        onLaneControls?()
    }
    func focus(_ window: ManagedWindow, hideBoard: Bool = true) {
        guard !editingDraft else { return }
        activeIDs[window.lane] = window.id
        if let slot = slotIDs(window.lane).firstIndex(of: window.id) { activeSlot[window.lane] = slot }
        selectedLane = window.lane
        if window.minimized { _ = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        // Raise the exact window before activating another app. Within the same
        // app, avoid activation entirely so its other windows stay in place.
        _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != window.pid {
            if NSRunningApplication(processIdentifier: window.pid)?.activate() != true { _ = FrontProcess.bring(pid: window.pid, window: window.element) }
            _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        }
    }
    // `arrange: false` only records the category; the window moves at the next Organize.
    func moveWindow(_ window: ManagedWindow, to lane: Lane, arrange arrangeNow: Bool = true) {
        markPlaced(window.id)
        // A window whose own category is shelved can still join any category.
        if enabledLanes.contains(lane), let outside = outsideGrid.firstIndex(where: { $0.id == window.id }) {
            var joined = outsideGrid.remove(at: outside); joined.lane = lane
            overrides[window.id] = lane; settings.windowCategories[window.id] = lane.rawValue; save()
            windows.append(joined)
            if arrangeNow && trusted && canUndo && !busy { reveal(joined) }
            selectedLane = lane; onLaneControls?()
            status = "\(windowLabel(window)) moved to \(name(lane))."
            return
        }
        guard enabledLanes.contains(lane), let index = windows.firstIndex(where: { $0.id == window.id }), window.lane != lane else { return }
        let source = window.lane, previous = Set(slotIDs(source))
        overrides[window.id] = lane; settings.windowCategories[window.id] = lane.rawValue
        windows[index].lane = lane; save()
        if arrangeNow && trusted && canUndo && !busy {
            let replacements = Set(slotIDs(source)).subtracting(previous).subtracting([""])
            _ = apply(source, presentationOnly: true, onlyIDs: replacements)
            for replacement in visibleItems(source) where replacements.contains(replacement.id) { _ = AXUIElementPerformAction(replacement.element, kAXRaiseAction as CFString) }
            reveal(windows[index])
        }
        selectedLane = lane; onLaneControls?()
        status = "\(windowLabel(window)) moved to \(name(lane))."
    }
    @discardableResult func splitCategory(_ source: Lane, sideBySide: Bool) -> Lane? {
        guard enabledLanes.contains(source) else { return nil }
        let rect = editorRect(source)
        var first = rect, second = rect
        if sideBySide { first.size.width /= 2; second.origin.x += first.width; second.size.width = first.width }
        else { first.size.height /= 2; second.origin.y += first.height; second.size.height = first.height }
        let base = name(source); var suffix = 2
        while availableLanes.contains(where: { name($0) == "\(base) \(suffix)" }) { suffix += 1 }
        let category = CustomCategory(name: "\(base) \(suffix)")
        var rects = layoutRects(); rects[source.rawValue] = ZoneRect(first); rects[category.id] = ZoneRect(second)
        guard GridGeometry.valid(rects, lanes: enabledLanes + [category.lane]) else { status = "This region is too small to split again."; return nil }
        let sourceWindows = items(source)
        let moved = visibleItems(source).dropFirst().first ?? sourceWindows.first(where: { $0.id != activeWindow(source)?.id })
        rememberLayout()
        settings.customCategories.append(category); settings.customRects = rects
        settings.capacities[source.rawValue] = 1; settings.capacities[category.id] = 1
        settings.useCustomGrid = true
        if let moved, let index = windows.firstIndex(where: { $0.id == moved.id }) {
            overrides[moved.id] = category.lane; settings.windowCategories[moved.id] = category.id
            windows[index].lane = category.lane; visibleSlotIDs[category.lane] = [moved.id]
        }
        visibleSlotIDs[source] = WindowSlots.normalized(visibleSlotIDs[source] ?? [], ids: items(source).map(\.id), capacity: 1)
        selectedLane = category.lane; gridSelectionActive = true
        layoutChanged("\(base) split into two independent regions.")
        if trusted && canUndo && !busy { _ = apply(source); _ = apply(category.lane) }
        onLaneControls?()
        return category.lane
    }
    func assign(_ window: ManagedWindow, to lane: Lane, rememberApp: Bool = false) {
        if !rememberApp, enabledLanes.contains(lane) { moveWindow(window, to: lane); return }
        if lane == .media && !settings.showMediaShelf { restoreCategory(.media) }
        overrides[window.id] = lane
        if rememberApp {
            let appIDs = Set(windows.filter { $0.bundleID == window.bundleID }.map(\.id))
            overrides = overrides.filter { !appIDs.contains($0.key) }
            settings.windowCategories = settings.windowCategories.filter { !appIDs.contains($0.key) }
            settings.appRules[window.bundleID] = lane.rawValue; save()
        }
        refresh(silent: true)
        status = "\(window.appName) assigned to \(name(lane)). Arrange to apply."
        selectedTemplateChanged = true
    }
    func undo() {
        guard trusted else { status = "Enable window control to restore positions."; return }
        var failures = 0
        for saved in snapshot.values {
            _ = AXUIElementSetAttributeValue(saved.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            if !move(saved.element, to: saved.frame) { failures += 1 }
            _ = AXUIElementSetAttributeValue(saved.element, kAXMinimizedAttribute as CFString, saved.minimized ? kCFBooleanTrue : kCFBooleanFalse)
        }
        for (pid, hidden) in hiddenAppSnapshot where hidden { _ = NSRunningApplication(processIdentifier: pid)?.hide() }
        hiddenAppSnapshot.removeAll()
        onHideLaneControls?()
        snapshot.removeAll(); canUndo = false; managedIDs.removeAll(); pages.removeAll(); visibleSlotIDs.removeAll(); activeSlot.removeAll()
        refresh(silent: true)
        status = failures == 0 ? "Original window positions restored." : "Restored positions; \(failures) windows were closed or could not be resized."
    }
    func changeScreen(_ id: UInt32) {
        if canUndo { undo() }
        settings.screenID = id; save(); syncDisplayLayout(); refresh(); selectedTemplateChanged = true
    }
    // Each display keeps its own grid. Switching changes the grid and strips only;
    // windows move when you press Organize.
    static func displayKey(_ screen: NSScreen) -> String { "\(screen.localizedName) \(Int(screen.frame.width))×\(Int(screen.frame.height))" }
    func syncDisplayLayout(fresh: Bool = false) {
        guard let screen else { return }
        let firstTime = settings.activeDisplayKey == nil
        let changed = settings.switchDisplay(to: Self.displayKey(screen), kind: DisplayKind.of(screen.frame.size), fresh: fresh)
        save()
        guard changed else { return }
        presetPreview = nil; gridDraft = nil
        refresh(silent: true)
        if !enabledLanes.contains(selectedLane), let first = enabledLanes.first { selectedLane = first }
        onLaneControls?()
        status = firstTime ? "Lanes chose a layout made for this screen." : "Switched to your grid for \(screen.localizedName). Press Organize to arrange your windows."
    }
    func category(at point: CGPoint, in area: CGRect) -> Lane? {
        grid.enabledLanes.first { lane in
            let unit = grid.unitRect(for: lane)
            return Layout.frame(unit: unit, in: area, gap: 7).contains(point)
        }
    }
    func removeCategory(_ lane: Lane) {
        guard enabledLanes.count > 1, enabledLanes.contains(lane) else { return }
        // Keep the hole and the group's assignments so shelving is reversible.
        var rects = layoutRects(); rects.removeValue(forKey: lane.rawValue)
        settings.customRects = rects
        settings.useCustomGrid = true
        layoutHistory = []
        settings.hiddenLanes.append(lane.rawValue)
        if !settings.shelvedLanes.contains(lane.rawValue) { settings.shelvedLanes.append(lane.rawValue) }
        if lane == .media { settings.showMediaShelf = false }
        let fallback = enabledLanes.contains(.desktop) ? Lane.desktop : enabledLanes.first!
        if selectedLane == lane { selectedLane = fallback }
        activeIDs[lane] = nil; pages[lane] = nil
        save(); refresh(silent: true); selectedTemplateChanged = true
        onHideLaneControls?()
        status = "\(name(lane)) moved to the category shelf. Drag it back to restore its group."
        if trusted && canUndo { arrange(hideBoard: false) }
    }
    func restoreCategory(_ lane: Lane, at point: CGPoint? = nil) {
        guard availableLanes.contains(lane), !enabledLanes.contains(lane) else { return }
        if !settings.customRects.isEmpty, !enabledLanes.contains(lane) {
            guard let restored = GridGeometry.restoring(lane, rects: layoutRects(), active: enabledLanes, at: point) else {
                status = "Make room by resizing another category, then restore \(name(lane))."; return
            }
            settings.customRects = restored
        }
        layoutHistory = []
        settings.hiddenLanes.removeAll { $0 == lane.rawValue }
        settings.useCustomGrid = true
        settings.shelvedLanes.removeAll { $0 == lane.rawValue }
        if lane == .media { settings.showMediaShelf = true }
        save(); refresh(silent: true); selectedTemplateChanged = true
        selectedLane = lane
        status = "\(name(lane)) restored. Click Apply this grid to use this layout."
        if trusted && canUndo { arrange(hideBoard: false) }
    }
    func selectGridCategory(_ lane: Lane) {
        selectedLane = lane; gridSelectionActive = true; onGridSelection?()
    }
    func name(_ lane: Lane) -> String { settings.name(lane) }
    func windowLabel(_ window: ManagedWindow) -> String {
        if let typed = settings.windowLabels[window.id] { return typed }
        guard settings.shortTabNames else { return window.title }
        let label = TitleSummary.label(title: window.title, appName: window.appName, bundleID: window.bundleID)
        // Two windows of one messaging app in a category: add which conversation.
        let app = TitleSummary.clean(window.appName)
        if label == app, windows.contains(where: { $0.id != window.id && $0.lane == window.lane && $0.bundleID == window.bundleID }) {
            let detail = TitleSummary.shortTitle(window.title, appName: window.appName)
            if detail != app { return "\(app) · \(detail)" }
        }
        return label
    }
    func beginRenamingWindow(_ window: ManagedWindow) { renameWindowID = window.id; onShow?() }
    func renameWindow(_ id: String, name: String) {
        let text = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        if text.isEmpty { settings.windowLabels.removeValue(forKey: id) } else { settings.windowLabels[id] = text }
        save()
    }
    func reorderTab(_ values: [String], before target: ManagedWindow, after: Bool = false) -> Bool {
        guard let value = values.first, let source = windows.first(where: { $0.id == (value.hasPrefix("tab:") ? String(value.dropFirst(4)) : value) }), source.lane == target.lane else { return false }
        let ids = WindowSlots.reordered(items(target.lane).map(\.id), source: source.id, before: target.id, after: after)
        let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        windows = windows.filter { $0.lane != target.lane } + ids.compactMap { byID[$0] }
        settings.windowOrder[target.lane.rawValue] = ids; save()
        status = "\(name(target.lane)) tab order saved. Visible windows stay in place."
        return true
    }
    func handleStripKey(_ action: StripKeyAction) {
        guard let lane = hoveredLane else { return }
        switch action {
        case .cycle(let delta): cycleWindow(lane, delta: delta)
        case .select(let index):
            let all = items(lane)
            if all.indices.contains(index) { reveal(all[index]) }
        }
    }
    // Hover targeting changes the picker, without activating or raising an app.
    func targetSlot(_ lane: Lane, index: Int) {
        let slots = slotIDs(lane)
        guard slots.indices.contains(index), activeSlot[lane] != index else { return }
        activeSlot[lane] = index
    }
    func selectSlot(_ lane: Lane, index: Int) {
        let slots = slotIDs(lane)
        guard slots.indices.contains(index) else { return }
        activeSlot[lane] = index
        if let window = items(lane).first(where: { $0.id == slots[index] }) { focus(window, hideBoard: false) }
    }
    func nextWindowLabel(_ lane: Lane) -> String {
        guard let id = WindowSlots.nextID(ids: items(lane).map(\.id), slots: slotIDs(lane), slot: activeSlot[lane] ?? 0, delta: 1), let window = items(lane).first(where: { $0.id == id }) else { return "No windows" }
        return windowLabel(window)
    }
    func slotLabel(_ lane: Lane, index: Int) -> String {
        let count = settings.capacity(lane)
        if count == 2 {
            let frames = Layout.tiles(in: laneFrame(lane), count: count, gap: settings.gap, lane: lane)
            return frames[0].minY == frames[1].minY ? (index == 0 ? "Left" : "Right") : (index == 0 ? "Top" : "Bottom")
        }
        return "Slot \(index + 1)"
    }
    var availableLanes: [Lane] { settings.availableLanes }
    func addCategory(name input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { status = "Give the category a name."; return false }
        let category = CustomCategory(name: String(trimmed.prefix(40)))
        guard let rects = GridGeometry.restoring(category.lane, rects: layoutRects(), active: enabledLanes) else {
            status = "Make room by resizing a category before adding another one."; return false
        }
        settings.customCategories.append(category); settings.customRects = rects
        settings.capacities[category.id] = 1
        selectedLane = category.lane; gridSelectionActive = true; layoutHistory = []
        save(); refreshRunningApps(); layoutChanged("\(category.name) created.")
        return true
    }
    func renameCategory(_ lane: Lane, name input: String) {
        let text = String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !text.isEmpty else { return }
        settings.categoryNames[lane.rawValue] = text; save()
    }
    func deleteSelectedCategory() {
        guard gridSelectionActive else { return }
        if enabledLanes.count <= 1 { status = "Keep at least one category. Add another before deleting this one."; return }
        removeCategory(selectedLane)
    }
    // Runs a grid edit against the draft. The screen, your windows and the saved
    // settings stay exactly as they are; the result becomes the draft shown in the
    // Lanes window, or disappears if it matches what is applied.
    func editGrid(_ body: () -> Void) {
        guard !editingDraft else { body(); return }
        presetPreview = nil
        let live = settings
        let state = (windows, outsideGrid, overrides, visibleSlotIDs, activeIDs, activeSlot, pages)
        let laneControls = onLaneControls, hide = onHide
        onLaneControls = nil; onHide = nil
        settings = gridDraft ?? live
        editingDraft = true
        body()
        editingDraft = false
        let edited = settings
        settings = live
        (windows, outsideGrid, overrides, visibleSlotIDs, activeIDs, activeSlot, pages) = state
        onLaneControls = laneControls; onHide = hide
        gridDraft = Self.sameGrid(edited, live) ? nil : edited
    }
    static func sameGrid(_ a: Settings, _ b: Settings) -> Bool {
        a.enabledLanes == b.enabledLanes && a.customCategories == b.customCategories && a.categoryNames == b.categoryNames &&
            a.windowCategories == b.windowCategories && a.placedWindows == b.placedWindows && a.placements == b.placements && a.gap == b.gap &&
            a.enabledLanes.allSatisfy { a.unitRect(for: $0) == b.unitRect(for: $0) && a.capacity($0) == b.capacity($0) }
    }
    // Apply: the draft becomes the grid your screen uses, and windows are arranged into it.
    func applyGridDraft() {
        guard gridDraft != nil, commitPendingGrid() else { return }
        if trusted { arrange(hideBoard: false) } else { onLaneControls?(); status = "Grid saved. Enable window control to arrange your apps." }
    }
    private func commitGridDraft() {
        guard let draft = gridDraft else { return }
        gridDraft = nil
        let before = layoutRects()
        let previous = currentGridLayout(name: "Previous layout")
        let chosen = Dictionary(uniqueKeysWithValues: enabledLanes.compactMap { lane in activeWindow(lane).map { (lane, $0.id) } })
        settings.apply(draft.displayLayout(kind: .wide))
        recenterMovedStrips(changedFrom: before)
        settings.customCategories = draft.customCategories
        settings.categoryNames = draft.categoryNames
        settings.windowCategories = draft.windowCategories
        settings.previousLayout = previous
        settings.placements = draft.placements
        settings.placedWindows = draft.placedWindows
        settings.gap = draft.gap
        overrides = settings.windowCategories.compactMapValues(Lane.init(rawValue:))
        // Draft editing intentionally restores the live slot state. Apply must
        // now normalize it for the new count without losing the chosen pane.
        for lane in enabledLanes {
            let capacity = settings.capacity(lane)
            let ids = items(lane).map(\.id)
            var slots = WindowSlots.normalized(visibleSlotIDs[lane] ?? [], ids: ids, capacity: capacity)
            if let id = chosen[lane], ids.contains(id) {
                let target = min(activeSlot[lane] ?? 0, capacity - 1)
                slots = WindowSlots.replacing(slots, with: id, at: target)
                activeIDs[lane] = id
                activeSlot[lane] = slots.firstIndex(of: id) ?? target
            }
            visibleSlotIDs[lane] = slots
        }
        save()
        if !enabledLanes.contains(selectedLane), let first = enabledLanes.first { selectedLane = first }
    }
    // A strip you dragged keeps its spot only while its category's box stays the
    // same; when the box changes, the strip goes back to the middle of its top edge.
    func recenterMovedStrips(changedFrom before: [String: ZoneRect]) {
        let after = layoutRects()
        for key in Array(settings.stripPositions.keys) where before[key] != after[key] { settings.stripPositions.removeValue(forKey: key) }
    }
    func discardGridDraft() {
        gridDraft = nil; editorPreview = nil
        status = "Grid changes discarded. Your screen is as it was."
    }
    func layoutRects() -> [String: ZoneRect] {
        Dictionary(uniqueKeysWithValues: grid.enabledLanes.map { ($0.rawValue, ZoneRect(grid.unitRect(for: $0))) })
    }
    func editorRect(_ lane: Lane) -> CGRect { editorPreview?[lane.rawValue]?.cgRect ?? grid.unitRect(for: lane) }
    func commitGridResize(_ rects: [String: ZoneRect], lane: Lane) {
        guard GridGeometry.valid(rects, lanes: enabledLanes), rects != layoutRects() else { editorPreview = nil; return }
        rememberLayout(); settings.customRects = rects; editorPreview = nil
        layoutChanged("\(name(lane)) and its shared borders resized.")
    }
    func rememberLayout() {
        layoutHistory.append(settings)
        if layoutHistory.count > 30 { layoutHistory.removeFirst() }
    }
    func validEdit(_ lane: Lane, rect: CGRect) -> Bool {
        var rects = layoutRects(); rects[lane.rawValue] = ZoneRect(rect)
        return GridGeometry.valid(rects, lanes: grid.enabledLanes)
    }
    func editCategory(_ lane: Lane, rect: CGRect) {
        guard enabledLanes.contains(lane), validEdit(lane, rect: rect) else {
            status = "That region overlaps another category or extends beyond the display. Shrink or move a neighbor first."
            return
        }
        guard settings.unitRect(for: lane) != rect else { return }
        rememberLayout()
        var rects = layoutRects(); rects[lane.rawValue] = ZoneRect(rect)
        settings.customRects = rects; layoutChanged("\(name(lane)) resized / positioned.")
    }
    func layoutChanged(_ message: String) {
        settings.useCustomGrid = true
        save(); selectedTemplateChanged = true
        status = message + " Organize keeps these sizes. Auto layout chooses a new grid."
    }
    func undoLayout() {
        guard let old = layoutHistory.popLast() else { return }
        settings.hiddenLanes = old.hiddenLanes; settings.shelvedLanes = old.shelvedLanes
        settings.customCategories = old.customCategories; settings.showMediaShelf = old.showMediaShelf
        settings.windowCategories = old.windowCategories
        overrides = old.windowCategories.compactMapValues(Lane.init(rawValue:))
        for index in windows.indices {
            let category = overrides[windows[index].id] ?? Classifier.lane(bundleID: windows[index].bundleID, appName: windows[index].appName, title: windows[index].title, rules: settings.appRules)
            windows[index].lane = enabledLanes.contains(category) ? category : enabledLanes[0]
        }
        if !enabledLanes.contains(selectedLane) { selectedLane = enabledLanes[0] }
        settings.customRects = old.customRects; settings.template = old.template
        settings.splits = old.splits; settings.placements = old.placements
        settings.capacities = old.capacities
        layoutChanged("Previous grid restored.")
    }
    // What dropping a dragged category would do, shown live in the grid editor.
    struct SnapHint: Equatable { let lane: Lane; let plan: GridGeometry.SnapPlan }
    @Published var snapHint: SnapHint?
    func snapPlan(_ lane: Lane, candidate: CGRect, at point: CGPoint) -> GridGeometry.SnapPlan {
        GridGeometry.snapPlan(lane, candidate: candidate, at: point, rects: layoutRects(), lanes: grid.enabledLanes)
    }
    func dropCategory(_ lane: Lane, candidate: CGRect, at point: CGPoint) {
        snapHint = nil
        switch snapPlan(lane, candidate: candidate, at: point) {
        case .move(let rect): editCategory(lane, rect: rect)
        case .swap(let target): swapCategories(lane, target)
        case .fit(let rects):
            rememberLayout(); settings.customRects = rects
            layoutChanged("\(name(lane)) moved into the free space.")
        case .none: status = "\(name(lane)) does not fit there. Drop it on another category to swap them."
        }
    }
    func swapCategories(_ source: Lane, _ target: Lane) {
        guard source != target, enabledLanes.contains(source), enabledLanes.contains(target) else { return }
        rememberLayout()
        var rects = layoutRects()
        let sourceRect = rects[source.rawValue]; rects[source.rawValue] = rects[target.rawValue]; rects[target.rawValue] = sourceRect
        settings.customRects = rects
        layoutChanged("\(name(source)) and \(name(target)) swapped.")
    }
    func resetPlacements() {
        rememberLayout(); settings.customRects = [:]; settings.placements = [:]
        settings.splits = [0.23, 0.42, 0.77, 0.56]
        layoutChanged("Category positions reset.")
    }
    func receiveDrop(_ values: [String], into target: Lane) -> Bool {
        var handled = false
        for value in values {
            if value.hasPrefix("lane:"), let source = Lane(rawValue: String(value.dropFirst(5))) {
                guard availableLanes.contains(source) else { continue }
                if enabledLanes.contains(source) { swapCategories(source, target) }
                else { restoreCategory(source, at: CGPoint(x: editorRect(target).midX, y: editorRect(target).midY)) }
                handled = enabledLanes.contains(source)
            } else if let window = windows.first(where: { $0.id == (value.hasPrefix("tab:") ? String(value.dropFirst(4)) : value) }) {
                assign(window, to: target); handled = true
            }
        }
        return handled
    }
    func receiveShelfDrop(_ values: [String]) -> Bool {
        guard enabledLanes.count > 1, let value = values.first(where: { $0.hasPrefix("lane:") }),
              let lane = Lane(rawValue: String(value.dropFirst(5))), enabledLanes.contains(lane) else { return false }
        removeCategory(lane); return !enabledLanes.contains(lane)
    }
    func receiveWorkspaceDrop(_ values: [String], at point: CGPoint, in size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0, CGRect(origin: .zero, size: size).contains(point),
              let value = values.first(where: { $0.hasPrefix("lane:") }),
              let lane = Lane(rawValue: String(value.dropFirst(5))), availableLanes.contains(lane) else { return false }
        if enabledLanes.contains(lane) {
            guard let target = category(at: point, in: CGRect(origin: .zero, size: size)) else { return false }
            swapCategories(lane, target)
        } else { restoreCategory(lane, at: CGPoint(x: point.x / size.width, y: point.y / size.height)) }
        return enabledLanes.contains(lane)
    }
    func currentGridLayout(name: String, from source: Settings? = nil) -> SavedGridLayout {
        let source = source ?? settings
        let rects = Dictionary(uniqueKeysWithValues: source.enabledLanes.map { ($0.rawValue, ZoneRect(source.unitRect(for: $0))) })
        return SavedGridLayout(name: name, rects: rects, capacities: source.capacities, lanes: source.enabledLanes.map(\.rawValue), gap: source.gap, categories: source.customCategories, categoryNames: source.categoryNames, windowCategories: source.windowCategories)
    }
    @discardableResult func saveGridLayout(name input: String) -> Bool {
        let name = String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !name.isEmpty else { return false }
        var uniqueName = name; var suffix = 2
        while settings.savedLayouts.contains(where: { $0.name == uniqueName }) { uniqueName = "\(name) \(suffix)"; suffix += 1 }
        var layout = currentGridLayout(name: uniqueName, from: grid)
        if let preview = presetPreview {
            if let id = preview.savedID, let saved = settings.savedLayouts.first(where: { $0.id == id }) {
                layout = saved; layout.id = UUID().uuidString; layout.name = uniqueName
            } else {
                layout.rects = preview.rects; layout.lanes = preview.lanes.map(\.rawValue)
            }
        }
        settings.savedLayouts.append(layout); save()
        status = "\(uniqueName) saved with category sizes and windows shown at once."
        return true
    }
    func loadGridLayout(_ layout: SavedGridLayout) {
        let lanes = layout.lanes.compactMap(Lane.init(rawValue:))
        let available = Lane.allCases + layout.categories.map(\.lane) + settings.customCategories.map(\.lane)
        guard !lanes.isEmpty, lanes.allSatisfy({ available.contains($0) }),
              GridGeometry.valid(layout.rects, lanes: lanes) else { status = "This saved layout contains unavailable categories or invalid regions."; return }
        rememberLayout(); settings.previousLayout = currentGridLayout(name: "Previous layout")
        for category in layout.categories where !settings.customCategories.contains(where: { $0.id == category.id }) { settings.customCategories.append(category) }
        settings.categoryNames.merge(layout.categoryNames, uniquingKeysWith: { _, saved in saved })
        settings.windowCategories = layout.windowCategories
        overrides = layout.windowCategories.compactMapValues(Lane.init(rawValue:))
        settings.hiddenLanes = availableLanes.filter { !lanes.contains($0) }.map(\.rawValue)
        settings.shelvedLanes = settings.hiddenLanes
        settings.showMediaShelf = lanes.contains(.media)
        settings.customRects = layout.rects; settings.capacities = layout.capacities
        settings.gap = min(28, max(4, layout.gap)); editorPreview = nil
        for index in windows.indices {
            let category = overrides[windows[index].id] ?? Classifier.lane(bundleID: windows[index].bundleID, appName: windows[index].appName, title: windows[index].title, rules: settings.appRules)
            windows[index].lane = lanes.contains(category) ? category : lanes[0]
        }
        if !lanes.contains(selectedLane) { selectedLane = lanes[0] }
        layoutChanged("\(layout.name) loaded.")
    }
    func restorePreviousLayout() {
        if let layout = settings.previousLayout { loadGridLayout(layout) }
    }
    func deleteSavedLayout(_ id: String) { settings.savedLayouts.removeAll { $0.id == id }; save() }
    func matchesLayout(_ layout: SavedGridLayout) -> Bool {
        layout.rects == layoutRects() && layout.lanes == enabledLanes.map(\.rawValue) &&
            enabledLanes.allSatisfy { settings.capacity($0) == layout.capacities[$0.rawValue] } && settings.gap == layout.gap
    }
    func showGrid() { onOverlay?(enabledLanes.map { ($0, rawLaneFrame($0)) }) }
    func setCapacity(_ lane: Lane, _ value: Int) {
        guard (1...4).contains(value), settings.capacity(lane) != value else { return }
        let oldSlots = slotIDs(lane), oldIndex = activeSlot[lane] ?? 0
        let chosen = activeWindow(lane)?.id
        rememberLayout()
        settings.capacities[lane.rawValue] = value; settings.useCustomGrid = true; pages[lane] = 0; selectedTemplateChanged = true
        var slots = WindowSlots.normalized(oldSlots, ids: items(lane).map(\.id), capacity: value)
        if oldIndex >= value, let chosen { slots = WindowSlots.replacing(slots, with: chosen, at: value - 1) }
        visibleSlotIDs[lane] = slots
        activeSlot[lane] = chosen.flatMap { slots.firstIndex(of: $0) } ?? min(oldIndex, value - 1)
        save()
        if trusted && canUndo && !busy { _ = apply(lane) }
        onLaneControls?()
        status = "\(name(lane)): \(value) window\(value == 1 ? "" : "s") shown at once. Other categories stay fixed."
    }
    func resetRules() {
        settings.appRules.removeAll(); settings.windowCategories.removeAll(); overrides.removeAll(); save(); refresh()
        selectedTemplateChanged = true
    }
}
