import AppKit
import SwiftUI
import Carbon
import QuartzCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var manager: WindowManager!
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var switcher: NSPanel?
    private var stripAnimators: [Lane: StripFrameAnimator] = [:]
    var overlays: [NSPanel] = []
    var laneControls: [NSPanel] = []
    var laneControlByID: [Lane: NSPanel] = [:]
    var hoverHotkeys: [EventHotKeyRef] = []
    var hotKeys: [EventHotKeyRef] = []
    var eventHandler: EventHandlerRef?
    var localKeyMonitor: Any?
    var globalTapMonitor: Any?
    var commandTap = DoubleCommandTap()
    var keyBindings: [(UInt32, UInt32, UInt32)] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A fresh launch of an installed update replaces an older Lanes instance.
        // Normal termination lets that instance restore its managed windows.
        let identifier = Bundle.main.bundleIdentifier ?? "com.bryson.lanes"
        let older = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter { $0.processIdentifier != getpid() }
        guard !older.isEmpty else { finishLaunching(); return }
        older.forEach { _ = $0.terminate() }
        Task { @MainActor in
            // Restoring a large ultrawide workload can take more than five
            // seconds. Give the previous instance time to finish its Undo.
            for _ in 0..<300 {
                if older.allSatisfy({ $0.isTerminated }) { finishLaunching(); return }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            // Avoid duplicate global shortcuts if an older instance refuses to quit.
            older.first?.activate(); NSApp.terminate(nil)
        }
    }
    func finishLaunching() {
        NSApp.setActivationPolicy(.accessory)
        manager = WindowManager()
        manager.onGridSelection = { [weak self] in self?.window?.makeFirstResponder(nil) }
        manager.onHoveredLaneChanged = { [weak self] in self?.updateHoverHotkeys() }
        manager.onTrustChanged = { [weak self] in self?.updateTapMonitor() }
        manager.onShow = { [weak self] in self?.showBoard() }
        manager.onHide = { [weak self] in self?.window.orderOut(nil) }
        manager.isBoardVisible = { [weak self] in self?.window.isVisible ?? false }
        manager.onKeepBoard = { [weak self] in NSApp.activate(); self?.window.makeKeyAndOrderFront(nil) }
        manager.onOverlay = { [weak self] frames in self?.showOverlay(frames) }
        manager.onLaneControls = { [weak self] in self?.showLaneControls() }
        manager.onHideLaneControls = { [weak self] in self?.hideLaneControls() }
        manager.onSwitcher = { [weak self] in self?.toggleSwitcher() }
        manager.adoptArrangement()
        buildMenuBar()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Lanes desktop organizer")
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
        let screen = NSScreen.screens.max(by: { $0.frame.width < $1.frame.width }) ?? NSScreen.main!
        let width = min(1240, screen.visibleFrame.width - 100), height = min(800, screen.visibleFrame.height - 60)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Lanes — Desktop Organizer"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.075, green: 0.09, blue: 0.083, alpha: 1)
        window.minSize = NSSize(width: 980, height: 570)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: BoardView(manager: manager))
        window.setFrameAutosaveName("LanesBoard")
        window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.midY - height / 2))
        registerHotkeys()
        updateTapMonitor()
        showBoard()
        if !manager.trusted { manager.showAccessHelp = true }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showBoard(); return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let manager, manager.canUndo && manager.trusted { manager.undo() }
    }
    func buildMenuBar() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Lanes", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Lanes", action: #selector(quit), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu, "Open Lanes", #selector(showBoardAction))
        add(menu, switcher?.isVisible == true ? "Hide lane switcher" : "Show lane switcher", #selector(toggleSwitcherAction))
        menu.addItem(.separator())
        let arrange = add(menu, manager.settings.doubleRightCommand ? "Organize desktop    Right Command twice" : "Organize desktop    Control + Option + Command + Return", #selector(arrangeAction)); arrange.isEnabled = manager.trusted
        let undo = add(menu, "Restore original windows    Control + Option + Command + Z", #selector(undoAction)); undo.isEnabled = manager.canUndo
        menu.addItem(.separator())
        for lane in manager.enabledLanes {
            let item = NSMenuItem(title: "\(manager.name(lane)) · \(manager.items(lane).count) windows", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let next = add(sub, Lane.allCases.firstIndex(of: lane).map { "Next window    Control + Option + Command + \($0 + 1)" } ?? "Next window", #selector(cycleAction)); next.representedObject = lane.rawValue
            let previous = add(sub, "Previous window", #selector(previousAction)); previous.representedObject = lane.rawValue
            sub.addItem(.separator())
            for window in manager.items(lane) {
                let title = String("\(window.appName) — \(window.title)".prefix(85))
                let entry = add(sub, title, #selector(windowAction)); entry.representedObject = window.id
                if let icon = window.icon?.copy() as? NSImage { icon.size = NSSize(width: 16, height: 16); entry.image = icon }
            }
            item.submenu = sub; menu.addItem(item)
        }
        menu.addItem(.separator())
        add(menu, "Show grid boundaries", #selector(gridAction))
        add(menu, "Take the tour", #selector(tourAction))
        add(menu, "Keyboard controls…", #selector(keyboardHelp))
        add(menu, "Quit Lanes", #selector(quit))
        menu.autoenablesItems = false
    }
    @discardableResult func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item); return item
    }
    func showBoard() {
        guard manager != nil, window != nil else { return }
        manager.hoveredLane = nil
        manager.refresh(silent: true)
        manager.rememberWorkingWindow()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
    @objc func showBoardAction() { showBoard() }
    @objc func tourAction() { showBoard(); manager.startTour() }
    @objc func arrangeAction() { manager.autoOrganize() }
    @objc func undoAction() { manager.undo() }
    @objc func cycleAction(_ sender: NSMenuItem) { if let id = sender.representedObject as? String, let lane = Lane(rawValue: id) { manager.cycleWindow(lane) } }
    @objc func previousAction(_ sender: NSMenuItem) { if let id = sender.representedObject as? String, let lane = Lane(rawValue: id) { manager.cycleWindow(lane, delta: -1) } }
    @objc func windowAction(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let window = manager.windows.first(where: { $0.id == id }) { manager.reveal(window) }
    }
    @objc func gridAction() { manager.showGrid() }
    @objc func toggleSwitcherAction() { toggleSwitcher() }
    @objc func keyboardHelp() {
        showBoard()
        let alert = NSAlert()
        alert.messageText = "Your windows, from the keyboard"
        alert.informativeText = "Double-tap Right Command to organize your desktop. You can turn this off in Preferences.\n\nHover a category strip and scroll, press Left/Right, or use 1–9 (0 selects window 10) to sift. Two-window categories have direct Top/Bottom or Left/Right targets. Strips on the windows fade to a faint outline when idle.\nBackspace deletes a selected grid category (outside text fields).\n\nOther commands start with Control–Option–Command.\n\n1–7: cycle individual windows in each category\nTab: cycle the focused window’s category\nShift–Tab: cycle backward\nShift–1…7: send the focused window to a category and resize it\nArrow keys: nudge by 24 pt inside its lane\nShift–arrow keys: resize by 24 pt\nReturn: auto-sort the desktop\nZ: restore original windows\n\n1 Terminal · 2 Simulators · 3 Previews · 4 Desktop · 5 Messaging · 6 Mini players · 7 Browser\n\nSet Windows shown at once to 1 to create one-window clusters for Messaging or your Arc windows. Arc windows are tracked separately."
        alert.addButton(withTitle: "Got it")
        alert.beginSheetModal(for: window)
    }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Lanes", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.2", .credits: NSAttributedString(string: "A place for every window. Built for ultrawide workflows.")])
    }
    @objc func quit() { manager.save(); NSApp.terminate(nil) }
    func registerHotkeys() {
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let error = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard error == noErr else { return error }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            let id = identifier.id
            DispatchQueue.main.async { delegate.handleHotkey(id) }
            return noErr
        }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        if installed != noErr { manager.status = "Global keyboard handler could not start. Use the lane counter buttons." }
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let shift = modifiers | UInt32(shiftKey)
        let keys: [(UInt32, UInt32, UInt32)] = [
            (1, UInt32(kVK_Space), modifiers), (2, UInt32(kVK_Return), modifiers), (3, UInt32(kVK_ANSI_Z), modifiers),
            (4, UInt32(kVK_Tab), modifiers), (5, UInt32(kVK_Tab), shift),
            (10, UInt32(kVK_ANSI_1), modifiers), (11, UInt32(kVK_ANSI_2), modifiers), (12, UInt32(kVK_ANSI_3), modifiers), (13, UInt32(kVK_ANSI_4), modifiers), (14, UInt32(kVK_ANSI_5), modifiers), (15, UInt32(kVK_ANSI_6), modifiers),
            (20, UInt32(kVK_ANSI_1), shift), (21, UInt32(kVK_ANSI_2), shift), (22, UInt32(kVK_ANSI_3), shift), (23, UInt32(kVK_ANSI_4), shift), (24, UInt32(kVK_ANSI_5), shift), (25, UInt32(kVK_ANSI_6), shift),
            (16, UInt32(kVK_ANSI_7), modifiers), (26, UInt32(kVK_ANSI_7), shift),
            (30, UInt32(kVK_LeftArrow), modifiers), (31, UInt32(kVK_RightArrow), modifiers), (32, UInt32(kVK_UpArrow), modifiers), (33, UInt32(kVK_DownArrow), modifiers),
            (40, UInt32(kVK_LeftArrow), shift), (41, UInt32(kVK_RightArrow), shift), (42, UInt32(kVK_UpArrow), shift), (43, UInt32(kVK_DownArrow), shift)
        ]
        keyBindings = keys
        for (id, key, mods) in keys {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(key, mods, EventHotKeyID(signature: 0x4C414E45, id: id), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { hotKeys.append(reference) }
            else { manager.status = "Some global shortcuts are already in use. The menu bar controls still work." }
        }
        // Local key events (including app-directed accessibility automation) can
        // bypass Carbon's global dispatcher. Handle the same chords in the board.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                self.observeCommandTap(event)
                guard event.type == .keyDown else { return false }
                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
                if CategoryDeletionKey.shouldDelete(keyCode: event.keyCode, hasModifiers: !flags.isEmpty,
                    gridSelected: self.manager.gridSelectionActive,
                    isEditingText: self.window.firstResponder is NSTextView || self.window.firstResponder is NSTextField,
                    boardIsKey: NSApp.keyWindow === self.window) {
                    self.manager.editGrid { self.manager.deleteSelectedCategory() }; return true
                }
                if let action = StripKeyAction.action(keyCode: event.keyCode, hasModifiers: !flags.isEmpty, hovering: self.pointerOnHoveredStrip()) {
                    self.manager.handleStripKey(action); return true
                }
                let required: NSEvent.ModifierFlags = [.command, .option, .control]
                guard flags.isSuperset(of: required) else { return false }
                let mods = UInt32(controlKey | optionKey | cmdKey) | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
                guard let binding = self.keyBindings.first(where: { $0.1 == UInt32(event.keyCode) && $0.2 == mods }) else { return false }
                self.handleHotkey(binding.0)
                return true
            }
            return handled ? nil : event
        }
    }

    func updateHoverHotkeys() {
        hoverHotkeys.forEach { UnregisterEventHotKey($0) }; hoverHotkeys = []
        guard manager.hoveredLane != nil else { return }
        for (index, binding) in StripKeyAction.bindings.enumerated() {
            let id = UInt32(50 + index), key = UInt32(binding.0)
            var reference: EventHotKeyRef?
            if RegisterEventHotKey(key, 0, EventHotKeyID(signature: 0x4C414E45, id: id), GetApplicationEventTarget(), 0, &reference) == noErr, let reference { hoverHotkeys.append(reference) }
        }
    }
    func pointerOnHoveredStrip() -> Bool {
        guard let lane = manager.hoveredLane else { return false }
        return StripHoverCheck.contains(laneControlByID[lane]?.frame, NSEvent.mouseLocation)
    }
    // A hover that outlived the pointer must not swallow typing: release the
    // strip keys, then hand the key press to the app you are typing in.
    func passThrough(_ key: UInt16) {
        manager.hoveredLane = nil
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] { CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)?.post(tap: .cghidEventTap) }
    }
    func updateTapMonitor() {
        if let globalTapMonitor { NSEvent.removeMonitor(globalTapMonitor); self.globalTapMonitor = nil }
        commandTap.cancel()
        guard manager.trusted else { return }
        globalTapMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.observeCommandTap(event) }
        }
    }
    func observeCommandTap(_ event: NSEvent) {
        guard manager.settings.doubleRightCommand else { commandTap.cancel(); return }
        guard event.type == .flagsChanged else { commandTap.cancel(); return }
        let modifiers = event.modifierFlags
        // NX_DEVICELCMDKEYMASK is 0x08. Reject a held left Command as well.
        let other = !modifiers.intersection([.option, .control, .shift, .function]).isEmpty || modifiers.rawValue & 0x08 != 0
        if commandTap.flags(keyCode: event.keyCode, commandDown: modifiers.contains(.command), otherModifiers: other, time: event.timestamp) {
            manager.autoOrganize()
        }
    }

    func handleHotkey(_ id: UInt32) {
        switch id {
        case 1: if window.isVisible { window.orderOut(nil) } else { showBoard() }
        case 2: manager.autoOrganize()
        case 3: manager.undo()
        case 4: manager.cycleFocused()
        case 5: manager.cycleFocused(delta: -1)
        case 50...61:
            let binding = StripKeyAction.bindings[Int(id - 50)]
            if pointerOnHoveredStrip() { manager.handleStripKey(binding.1) } else { passThrough(binding.0) }
        case 10...16: manager.cycleWindow(Lane.allCases[Int(id - 10)])
        case 20...26: manager.sendFocused(to: Lane.allCases[Int(id - 20)])
        case 30...33, 40...43:
            let direction = Int(id % 10)
            let dx: CGFloat = direction == 0 ? -24 : direction == 1 ? 24 : 0
            let dy: CGFloat = direction == 2 ? -24 : direction == 3 ? 24 : 0
            manager.adjustFocused(dx: dx, dy: dy, resize: id >= 40)
        default: break
        }
    }
    func toggleSwitcher() {
        if let switcher, switcher.isVisible { switcher.orderOut(nil); return }
        if switcher == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 860, height: 56), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Lanes Switcher"
            panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = true; panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: SwitcherView(manager: manager, showBoard: { [weak self] in self?.showBoard() }, close: { [weak panel] in panel?.orderOut(nil) }))
            switcher = panel
        }
        if let screen = manager.screen {
            switcher?.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 430, y: screen.visibleFrame.minY + 14))
        }
        switcher?.orderFrontRegardless()
    }
    func hideLaneControls() {
        stripAnimators.values.forEach { $0.cancel() }; stripAnimators = [:]
        laneControls.forEach { $0.close() }; laneControls = []; laneControlByID = [:]
        manager.hoveredLane = nil
    }
    func showLaneControls() {
        guard manager.settings.showLaneControls, manager.trusted, manager.canUndo else { hideLaneControls(); return }
        let wanted = Set(manager.enabledLanes)
        for lane in Array(laneControlByID.keys) where !wanted.contains(lane) {
            stripAnimators.removeValue(forKey: lane)?.cancel()
            laneControlByID.removeValue(forKey: lane)?.close()
            if manager.hoveredLane == lane { manager.hoveredLane = nil }
        }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        for lane in manager.enabledLanes {
            // One window means nothing to switch: no strip at all, not a faded one.
            guard WindowStripMetrics.needsStrip(windowCount: manager.items(lane).count) else {
                stripAnimators.removeValue(forKey: lane)?.cancel()
                laneControlByID.removeValue(forKey: lane)?.close()
                if manager.hoveredLane == lane { manager.hoveredLane = nil }
                continue
            }
            let strip = manager.stripFrame(lane)
            let cocoaFrame = NSRect(x: strip.minX, y: mainHeight - strip.maxY, width: strip.width, height: strip.height)
            let panel: NSPanel
            if let existing = laneControlByID[lane] {
                panel = existing
                if manager.draggingStrip != lane {
                    let animator = stripAnimators[lane] ?? StripFrameAnimator()
                    stripAnimators[lane] = animator
                    animator.move(panel, to: cocoaFrame, animated: manager.settings.stripStyle(lane) == .expanding)
                }
            }
            else {
                panel = NSPanel(contentRect: cocoaFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
                panel.hasShadow = false; panel.isReleasedWhenClosed = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.contentView = NSHostingView(rootView: LaneWindowStrip(manager: manager, lane: lane, showBoard: { [weak self] in self?.showBoard() }))
                laneControlByID[lane] = panel
            }
            panel.title = "\(manager.name(lane)) — Lanes picker"
            // Floating panels stay above app windows; re-ordering on every
            // switch only costs time while scrolling.
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        laneControls = Array(laneControlByID.values)
    }
    func showOverlay(_ frames: [(Lane, CGRect)]) {
        overlays.forEach { $0.close() }; overlays.removeAll()
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        for (lane, frame) in frames {
            let cocoaFrame = NSRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
            let panel = NSPanel(contentRect: cocoaFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.ignoresMouseEvents = true
            panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces]; panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: OverlayView(lane: lane, name: manager.name(lane)))
            panel.orderFrontRegardless(); overlays.append(panel)
        }
        let current = overlays
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { current.forEach { $0.close() } }
    }
}

struct SwitcherView: View {
    @ObservedObject var manager: WindowManager
    let showBoard: () -> Void
    let close: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Button(action: showBoard) { Image(systemName: "rectangle.split.3x1.fill").font(.system(size: 19)).foregroundStyle(Color(red: 0.75, green: 0.88, blue: 0.58)).frame(width: 52, height: 52) }.buttonStyle(.plain)
            ForEach(manager.enabledLanes) { lane in
                Button { manager.cycleWindow(lane) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: lane.symbol).foregroundStyle(lane.color)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(manager.name(lane)).font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
                            Text(manager.windowCounter(lane)).font(.system(size: 8, design: .monospaced)).foregroundStyle(.gray)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.gray)
                    }.frame(maxWidth: .infinity).frame(height: 52)
                }.buttonStyle(.plain).help("Next window in \(manager.name(lane))")
            }
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(.gray).frame(width: 30, height: 52) }.buttonStyle(.plain)
        }.background(Color(red: 0.07, green: 0.085, blue: 0.08).opacity(0.98))
            .clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.15))).padding(2)
    }
}
struct OverlayView: View {
    let lane: Lane
    let name: String
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(lane.color.opacity(0.08))
            RoundedRectangle(cornerRadius: 12).strokeBorder(lane.color.opacity(0.85), lineWidth: 3)
            Label(name, systemImage: lane.symbol).font(.system(size: 18, weight: .semibold))
                .padding(14).background(Color.black.opacity(0.85)).foregroundStyle(lane.color).clipShape(RoundedRectangle(cornerRadius: 8)).padding(16)
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}

// Grows and shrinks Expand-on-hover strips once per display refresh (120 Hz
// and up on fast displays) with an ease-out curve. Other moves are immediate.
@MainActor final class StripFrameAnimator: NSObject {
    private var link: CADisplayLink?
    private weak var panel: NSWindow?
    private var from = NSRect.zero, to = NSRect.zero, start: CFTimeInterval = 0
    private let duration: CFTimeInterval = 0.18
    func move(_ panel: NSWindow, to target: NSRect, animated: Bool) {
        if link != nil && to == target { return }
        if link == nil && panel.frame == target { return }
        // Only a change in width with the left and top edges fixed is a grow or shrink.
        let resize = abs(panel.frame.minX - target.minX) < 1 && abs(panel.frame.maxY - target.maxY) < 1 && abs(panel.frame.height - target.height) < 1
        guard animated, resize else { cancel(); panel.setFrame(target, display: true); return }
        cancel()
        self.panel = panel; from = panel.frame; to = target; start = CACurrentMediaTime()
        let link = panel.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }
    func cancel() { link?.invalidate(); link = nil }
    @objc private func step(_ link: CADisplayLink) {
        guard let panel else { cancel(); return }
        let t = min(1, (CACurrentMediaTime() - start) / duration)
        let eased = 1 - pow(1 - t, 3)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * eased }
        panel.setFrame(NSRect(x: mix(from.minX, to.minX), y: mix(from.minY, to.minY), width: mix(from.width, to.width), height: mix(from.height, to.height)), display: true)
        if t >= 1 { cancel() }
    }
}
