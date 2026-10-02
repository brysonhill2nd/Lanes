import AppKit
import SwiftUI
import ApplicationServices

extension Array { subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }

@main struct StripPreview {
    @MainActor static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("lanes-strip-preview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        // --mine previews with a copy of this Mac's own Lanes settings.
        if CommandLine.arguments.contains("--mine") {
            try? FileManager.default.copyItem(at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Lanes/settings.json"), to: fixture.appendingPathComponent("settings.json"))
        }
        let manager = WindowManager(settingsFile: fixture.appendingPathComponent("settings.json"), startPolling: false)
        manager.trusted = true
        if !CommandLine.arguments.contains("--mine") { manager.settings.hiddenLanes = [] }
        // --count N previews a category with N windows (default 6).
        let countArgument = CommandLine.arguments.firstIndex(of: "--count").flatMap { Int(CommandLine.arguments[safe: $0 + 1] ?? "") } ?? 6
        manager.windows = (0..<countArgument).map { index in
            ManagedWindow(id: "preview-\(index)", element: AXUIElementCreateApplication(getpid()), pid: getpid(), bundleID: "example.arc", appName: "Arc", title: "Workspace \(index + 1)", icon: NSImage(systemSymbolName: "globe", accessibilityDescription: nil), frame: CGRect(x: 0, y: 0, width: 1200, height: 800), minimized: false, lane: .browser)
        }
        manager.activeIDs[.browser] = "preview-0"
        func capture(_ host: NSView, _ name: String) throws {
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/" + name + ".png"))
        }
        if !CommandLine.arguments.contains("--board-only") {
        for style in WindowStripStyle.allCases {
            for slots in [1, 2] {
                manager.settings.windowStripStyle = style
                manager.settings.capacities["browser"] = slots
                // Expand on hover is rendered in its hovered, expanded state.
                manager.expandedStrip = style == .expanding ? .browser : nil
                let metrics = manager.displayedStripMetrics(.browser)
                let host = LaneScrollHostingView(rootView: AnyView(Color.clear))
                host.setStripContent(AnyView(LanePickerContent(manager: manager, lane: .browser, showBoard: {})))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: metrics.width, height: metrics.height), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isOpaque = false; window.backgroundColor = .clear; window.contentView = host
                host.setFrameSize(NSSize(width: metrics.width, height: metrics.height))
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
                let name = "strip-\(style.rawValue)-\(slots)"
                try capture(host, name)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.9))
                precondition(!host.visibility.visible, "bar must fade completely when idle")
                try capture(host, name + "-idle")
                host.setStripContent(AnyView(LanePickerContent(manager: manager, lane: .browser, showBoard: {})))
                precondition(!host.visibility.visible, "window updates must not reset idle fade")
                host.visibility.setHovered(true)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
                try capture(host, name + "-hover")
                print("Rendered \(style.title), \(slots) pane(s): \(Int(metrics.width)) × \(Int(metrics.height)); idle + hover")
            }
        }
        }
        manager.selectedLane = .browser
        manager.settings.capacities["browser"] = 2
        manager.saveGridLayout(name: "My ultrawide")
        let tour = CommandLine.arguments.contains("--tour")
        manager.settings.hasSeenTour = !tour
        let board = NSHostingView(rootView: BoardView(manager: manager))
        let boardWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 1020), styleMask: [.borderless], backing: .buffered, defer: false)
        boardWindow.contentView = board
        board.setFrameSize(NSSize(width: 1060, height: 1020))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        if CommandLine.arguments.contains("--apps") {
            if !CommandLine.arguments.contains("--mine") { manager.settings = .firstRun }; manager.refreshRunningApps()
            let sheet = NSHostingView(rootView: CategoryBoard(manager: manager, byWindow: CommandLine.arguments.contains("--windows")).padding(24).background(Color(red: 0.075, green: 0.09, blue: 0.083)))
            let sheetWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
            sheetWindow.contentView = sheet; sheet.setFrameSize(NSSize(width: 1040, height: 700))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
            try capture(sheet, CommandLine.arguments.contains("--windows") ? "app-categories-windows" : "app-categories")
            print("Rendered app categories")
            return
        }
        if CommandLine.arguments.contains("--first-run") {
            // What a new install shows, minus the tour card.
            manager.settings = .firstRun
            if CommandLine.arguments.contains("--laptop") { manager.settings.apply(manager.settings.laptopLayout()) }
            if CommandLine.arguments.contains("--snap") { manager.snapHint = .init(lane: .terminal, plan: .swap(.browser)) }
            manager.settings.hasSeenTour = true
            manager.windows = manager.windows.map { var w = $0; w.lane = .browser; return w }
            manager.selectedLane = .browser
            boardWindow.setContentSize(NSSize(width: 1240, height: 800)); board.setFrameSize(NSSize(width: 1240, height: 800))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
            try capture(board, CommandLine.arguments.contains("--snap") ? "snap-hint" : CommandLine.arguments.contains("--laptop") ? "first-run-laptop" : "first-run")
            print("Rendered first-run board")
            return
        }
        if CommandLine.arguments.contains("--preset") {
            manager.settings.hasSeenTour = true
            boardWindow.setContentSize(NSSize(width: 1240, height: 800)); board.setFrameSize(NSSize(width: 1240, height: 800))
            manager.previewPreset(.focus)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
            try capture(board, "preset-preview")
            print("Rendered preset preview")
            return
        }
        if tour {
            // The real Lanes window size. First the permission step, then every step with access on.
            boardWindow.setContentSize(NSSize(width: 1240, height: 800)); board.setFrameSize(NSSize(width: 1240, height: 800))
            for trusted in [false, true] {
                manager.trusted = trusted
                manager.startTour()
                for i in manager.tourSteps.indices where trusted || i == 0 {
                    manager.tourStep = i
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
                    try capture(board, "tour-\(trusted ? "" : "first-")\(i + 1)")
                }
            }
            print("Rendered tour steps")
            return
        }
        try capture(board, "board-preview")
        print("Rendered board with saved layouts, split controls and Browser side-by-side")
    }
}
