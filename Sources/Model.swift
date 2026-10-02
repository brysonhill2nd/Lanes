import Foundation
import CoreGraphics

struct Lane: RawRepresentable, Hashable, Codable, Identifiable, CaseIterable {
    let rawValue: String
    static let terminal = Lane(builtin: "terminal"), simulator = Lane(builtin: "simulator"), preview = Lane(builtin: "preview"), desktop = Lane(builtin: "desktop"), messaging = Lane(builtin: "messaging"), media = Lane(builtin: "media")
    static let browser = Lane(builtin: "browser")
    static let legacyCases: [Lane] = [.terminal, .simulator, .preview, .desktop, .messaging, .media]
    static let allCases: [Lane] = legacyCases + [.browser]
    private init(builtin: String) { rawValue = builtin }
    init?(rawValue: String) {
        guard Self.allCases.contains(where: { $0.rawValue == rawValue }) || (rawValue.hasPrefix("custom:") && UUID(uuidString: String(rawValue.dropFirst(7))) != nil) else { return nil }
        self.rawValue = rawValue
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let lane = Lane(rawValue: value) else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid category identifier") }
        self = lane
    }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
    var id: String { rawValue }
    var isCustom: Bool { rawValue.hasPrefix("custom:") }
    var title: String {
        switch self { case .terminal: return "Terminal"; case .simulator: return "Simulators"; case .preview: return "Previews"; case .desktop: return "Desktop"; case .messaging: return "Messaging"; case .media: return "Mini players"; case .browser: return "Browser"; default: return "Custom category" }
    }
    var symbol: String {
        switch self { case .terminal: return "terminal"; case .simulator: return "iphone"; case .preview: return "play.rectangle"; case .desktop: return "macwindow"; case .messaging: return "bubble.left.and.bubble.right"; case .media: return "pip"; case .browser: return "globe"; default: return "square.stack.3d.up" }
    }
    var hint: String {
        switch self { case .terminal: return "Shells & agents"; case .simulator: return "Devices & emulators"; case .preview: return "Video, documents & previews"; case .desktop: return "ChatGPT, editors & files"; case .messaging: return "Conversations & inboxes"; case .media: return "Picture-in-Picture & compact players"; case .browser: return "Arc & other browser windows"; default: return "Your category · assign individual windows or whole apps" }
    }
    var defaultCapacity: Int { self == .media || self == .browser || isCustom ? 1 : 2 }
}
struct CustomCategory: Codable, Identifiable, Equatable {
    var id: String = "custom:" + UUID().uuidString
    var name: String
    var lane: Lane { Lane(rawValue: id)! }
}

enum Template: String, CaseIterable, Codable, Identifiable {
    case build, focus, studio
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var subtitle: String {
        switch self { case .build: return "Code, test, stay connected"; case .focus: return "More room for your main work"; case .studio: return "Put your previews first" }
    }
    func rect(for lane: Lane, splits: [Double], includeMedia: Bool = true) -> CGRect {
        guard lane == .messaging || lane == .media else { return baseRect(for: lane, splits: splits) }
        let messaging = baseRect(for: .messaging, splits: splits)
        if !includeMedia { return lane == .media ? .zero : messaging }
        let shelf = messaging.height * 0.30
        if lane == .media { return CGRect(x: messaging.minX, y: messaging.maxY - shelf, width: messaging.width, height: shelf) }
        return CGRect(x: messaging.minX, y: messaging.minY, width: messaging.width, height: messaging.height - shelf)
    }
    private func baseRect(for lane: Lane, splits: [Double]) -> CGRect {
        let a = splits[0], b = splits[1], c = splits[2], h = splits[3]
        switch self {
        case .build:
            switch lane {
            case .terminal: return CGRect(x: 0, y: 0, width: a, height: 1)
            case .simulator: return CGRect(x: a, y: 0, width: b - a, height: 1)
            case .preview: return CGRect(x: b, y: 0, width: c - b, height: h)
            case .desktop: return CGRect(x: b, y: h, width: c - b, height: 1 - h)
            case .media: return .zero
            case .messaging: return CGRect(x: c, y: 0, width: 1 - c, height: 1)
            default: return .zero
            }
        case .focus:
            switch lane {
            case .terminal: return CGRect(x: a, y: 0, width: c - a, height: 1)
            case .simulator: return CGRect(x: 0, y: 0, width: a, height: h)
            case .preview: return CGRect(x: 0, y: h, width: a, height: 1-h)
            case .desktop: return CGRect(x: c, y: 0, width: 1-c, height: h)
            case .media: return .zero
            case .messaging: return CGRect(x: c, y: h, width: 1-c, height: 1-h)
            default: return .zero
            }
        case .studio:
            switch lane {
            case .preview: return CGRect(x: a, y: 0, width: c-a, height: 1)
            case .terminal: return CGRect(x: 0, y: 0, width: a, height: h)
            case .desktop: return CGRect(x: 0, y: h, width: a, height: 1-h)
            case .simulator: return CGRect(x: c, y: 0, width: 1-c, height: h)
            case .media: return .zero
            case .messaging: return CGRect(x: c, y: h, width: 1-c, height: 1-h)
            default: return .zero
            }
        }
    }
}

enum WindowStripStyle: String, Codable, CaseIterable, Identifiable {
    case compact, detailed, expanding
    var id: String { rawValue }
    var title: String { self == .expanding ? "Expand on hover" : rawValue.capitalized }
}
struct WindowStripMetrics {
    var width: Double
    var height: Double
    var reservedHeight: Double { height + 8 }
    static func needsStrip(windowCount: Int) -> Bool { windowCount > 1 }
    // Detailed strips: widest window chip, and the room taken by the handle,
    // name, pane chooser and counter (unscaled points).
    static let chipWidth = 200.0
    static func chipRoom(slots: Int) -> Double { 175 + (slots == 2 ? 110 : slots > 2 ? 32 : 0) }
    static func measure(style: WindowStripStyle, count: Int, scale: Double, availableWidth: Double, slots: Int = 1) -> WindowStripMetrics {
        let scale = min(1.5, max(0.8, scale.isFinite ? scale : 1))
        let dotsWidth = 24.0 + 18 + Double(max(0, min(16, count) - 1)) * 11
        // Expand on hover is laid out at its compact size; only hovering grows it.
        let small = style != .detailed
        // Detailed is as wide as its chips need, up to a full bar.
        let chips = min(760, chipRoom(slots: 1) + Double(max(2, min(16, count))) * chipWidth)
        let width = (small ? max(190, dotsWidth + 110) : chips) + (slots > 1 ? (slots == 2 ? 110 : 32) : 0)
        // Both styles are one rounded row; Detailed is only wider.
        let height = 32.0
        return WindowStripMetrics(width: max(1, min(availableWidth, width * scale)), height: height * scale)
    }
}

// A window as automatic placement saw it on one check.
struct SeenWindow: Equatable {
    let id: String
    let pid: Int32
    let frame: CGRect
}

enum TabSwitch {
    static func sameSpot(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 4 && abs(a.minY - b.minY) < 4 && abs(a.width - b.width) < 4 && abs(a.height - b.height) < 4
    }
    // Native tabs (Ghostty, Terminal, Finder) are separate windows: switching
    // tabs hides one window and shows another of the same app in the same spot.
    // Maps each newly seen tab window to the window it replaced.
    static func pairs(vanished: [SeenWindow], appeared: [SeenWindow]) -> [String: String] {
        var result: [String: String] = [:], used: Set<String> = []
        for window in appeared {
            guard let match = vanished.first(where: { !used.contains($0.id) && $0.pid == window.pid && sameSpot($0.frame, window.frame) }) else { continue }
            used.insert(match.id); result[window.id] = match.id
        }
        return result
    }
}

enum StackOrder {
    // Matches each window to the window server's front-to-back list. An app's
    // own window list is front-to-back too, so windows of one app stacked in
    // the same spot are told apart by their order within that app.
    // `windows` must be in each app's own order; returns id → position (0 = front).
    static func positions(windows: [SeenWindow], onScreen: [(pid: Int32, frame: CGRect)]) -> [String: Int] {
        var used: Set<Int> = [], result: [String: Int] = [:]
        for window in windows {
            guard let index = onScreen.indices.first(where: { !used.contains($0) && onScreen[$0].pid == window.pid && TabSwitch.sameSpot(onScreen[$0].frame, window.frame) }) else { continue }
            used.insert(index); result[window.id] = index
        }
        return result
    }
    // After a restart: which window shows in each tile, front window first.
    // Windows outside every tile are left for placement; slot "" means no window.
    static func adoptedSlots(tiles: [CGRect], windows: [SeenWindow], order: [String: Int]) -> (slots: [String], adopted: [String]) {
        var slots = Array(repeating: "", count: tiles.count), adopted: [String] = []
        for window in windows.sorted(by: { order[$0.id] ?? Int.max < order[$1.id] ?? Int.max }) {
            let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
            guard let tile = tiles.firstIndex(where: { TabSwitch.sameSpot($0, window.frame) || $0.contains(center) }) else { continue }
            adopted.append(window.id)
            if slots[tile].isEmpty && order[window.id] != nil { slots[tile] = window.id }
        }
        return (slots, adopted)
    }
}

enum NewWindowPlacement: String, CaseIterable, Identifiable {
    case center, leave, category
    var id: String { rawValue }
    var title: String {
        switch self { case .center: return "Center"; case .leave: return "Leave"; case .category: return "Category" }
    }
}

// Short, readable tab names made from window titles, on this Mac, with no AI.
// A name the user typed always wins over these.
enum TitleSummary {
    static let limit = 28
    static let trailingFillers: Set<String> = ["and", "or", "the", "of", "for", "to", "a", "an", "with", "in", "on", "at", "by", "from", "&", "+"]
    static func isMessagingApp(bundleID: String, appName: String) -> Bool {
        Classifier.lane(bundleID: bundleID, appName: appName, title: "", rules: [:]) == .messaging
    }
    // Apps and titles can carry invisible text-direction marks; drop them.
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"\p{Cf}"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    // Messaging apps show their own name; everything else its title, shortened.
    static func label(title: String, appName: String, bundleID: String) -> String {
        isMessagingApp(bundleID: bundleID, appName: appName) ? clean(appName) : shortTitle(title, appName: appName)
    }
    // The first meaningful part of a title: no agent status symbols or unread
    // counts in front, no app names, prices or user names after a separator.
    // A one-word name keeps the next part ("Atlas · Version Showcase"). Cut at
    // a word near `limit` characters, never ending on a filler like "and".
    static func shortTitle(_ title: String, appName: String) -> String {
        let app = clean(appName)
        var text = clean(title).replacingOccurrences(of: #"^[^\p{L}\p{N}(]+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"^\(\d+\+?\)\s*"#, with: "", options: .regularExpression)
        let parts = text.replacingOccurrences(of: #"\s+[|•·—–\-]\s+"#, with: "\u{1F}", options: .regularExpression)
            .components(separatedBy: "\u{1F}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { part in
                part.filter(\.isLetter).count >= 2 && part.caseInsensitiveCompare(app) != .orderedSame
            }
        guard var short = parts.first else { return app }
        if !short.contains(" "), parts.count > 1, parts[1].range(of: short, options: .caseInsensitive) == nil {
            short += " · " + parts[1]
        }
        // A long list stops at its first comma ("CITY APARTMENT HUNTING, Street…").
        if short.count > limit, let comma = short.firstIndex(of: ","), short.distance(from: short.startIndex, to: comma) >= 3 {
            short = String(short[..<comma])
        }
        if short.count > limit {
            let head = String(short.prefix(limit + 1))
            short = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? String(short.prefix(limit))
        }
        var words = short.split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last, trailingFillers.contains(last.lowercased()) || last == "·" { words.removeLast() }
        return words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,:;(-–—·"))
    }
}

// Built-in presets arrange whichever categories you have, including Browser and
// your own. The main category (selected in the sidebar) gets the most room, and
// categories with more windows get more room than empty ones.
enum PresetShape: String, CaseIterable, Identifiable {
    case columns, focus, mainSide
    var id: String { rawValue }
    var title: String { self == .columns ? "Columns" : self == .focus ? "Focus" : "Main + side" }
    var subtitle: String {
        switch self {
        case .columns: return "Every category side by side; busier ones are wider"
        case .focus: return "Your main category in the middle, the rest on both sides"
        case .mainSide: return "Your main category on the left, the rest stacked on the right"
        }
    }
    var symbol: String { self == .columns ? "rectangle.split.3x1" : self == .focus ? "rectangle.center.inset.filled" : "rectangle.lefthalf.inset.filled" }

    static func weight(_ count: Int) -> Double { (1 + Double(max(0, count))).squareRoot() }

    func rects(lanes: [Lane], main: Lane, windows: [Lane: Int]) -> [String: ZoneRect] {
        guard !lanes.isEmpty else { return [:] }
        let main = lanes.contains(main) ? main : lanes[0]
        let w = { (l: Lane) in PresetShape.weight(windows[l] ?? 0) * (l == main ? 1.4 : 1) }
        // Other categories, busiest first, so they sit nearest the main one.
        let others = lanes.filter { $0 != main }.sorted { (windows[$0] ?? 0) > (windows[$1] ?? 0) }
        var out: [String: ZoneRect] = [:]
        func column(_ items: [Lane], x: Double, width: Double) {
            let total = items.map(w).reduce(0, +)
            var y = 0.0
            for (i, l) in items.enumerated() {
                let h = i == items.count - 1 ? 1 - y : w(l) / total
                out[l.rawValue] = ZoneRect(CGRect(x: x, y: y, width: width, height: h)); y += h
            }
        }
        func columns(_ items: [Lane], x0: Double, width: Double) {
            let total = items.map(w).reduce(0, +)
            var x = x0
            for (i, l) in items.enumerated() {
                let cw = i == items.count - 1 ? x0 + width - x : width * w(l) / total
                out[l.rawValue] = ZoneRect(CGRect(x: x, y: 0, width: cw, height: 1)); x += cw
            }
        }
        if lanes.count == 1 { out[main.rawValue] = ZoneRect(CGRect(x: 0, y: 0, width: 1, height: 1)); return out }
        switch self {
        case .columns:
            columns(lanes, x0: 0, width: 1)
        case .focus:
            if others.count == 1 {
                out[main.rawValue] = ZoneRect(CGRect(x: 0, y: 0, width: 0.62, height: 1)); column(others, x: 0.62, width: 0.38)
            } else {
                let left = Array(others.enumerated().filter { $0.offset % 2 == 0 }.map(\.element))
                let right = Array(others.enumerated().filter { $0.offset % 2 == 1 }.map(\.element))
                column(left, x: 0, width: 0.25)
                out[main.rawValue] = ZoneRect(CGRect(x: 0.25, y: 0, width: 0.5, height: 1))
                column(right, x: 0.75, width: 0.25)
            }
        case .mainSide:
            out[main.rawValue] = ZoneRect(CGRect(x: 0, y: 0, width: 0.6, height: 1))
            if others.count <= 3 { column(others, x: 0.6, width: 0.4) }
            else {
                let half = (others.count + 1) / 2
                column(Array(others.prefix(half)), x: 0.6, width: 0.2)
                column(Array(others.dropFirst(half)), x: 0.8, width: 0.2)
            }
        }
        return out
    }
}

// Each display keeps its own grid, so a MacBook screen never inherits the
// ultrawide's five columns, and plugging the ultrawide back in restores its grid.
enum DisplayKind: String, Codable {
    case wide, standard
    static func of(_ size: CGSize) -> DisplayKind { size.height > 0 && size.width / size.height >= 2 ? .wide : .standard }
}
struct DisplayLayout: Codable, Equatable {
    var kind: DisplayKind
    var customRects: [String: ZoneRect]
    var capacities: [String: Int]
    var hiddenLanes: [String]
    var shelvedLanes: [String]
    var showMediaShelf: Bool
    var useCustomGrid: Bool
    var stripPositions: [String: StripPosition]
}
extension Settings {
    func displayLayout(kind: DisplayKind) -> DisplayLayout {
        DisplayLayout(kind: kind, customRects: customRects, capacities: capacities, hiddenLanes: hiddenLanes, shelvedLanes: shelvedLanes, showMediaShelf: showMediaShelf, useCustomGrid: useCustomGrid, stripPositions: stripPositions)
    }
    mutating func apply(_ d: DisplayLayout) {
        customRects = d.customRects; capacities = d.capacities; hiddenLanes = d.hiddenLanes; shelvedLanes = d.shelvedLanes
        showMediaShelf = d.showMediaShelf; useCustomGrid = d.useCustomGrid; stripPositions = d.stripPositions
    }
    // A laptop starting point from the categories in use: the main one (Browser when
    // present) on the left at 60%, Terminal and Messaging stacked on the right, one
    // window at a time each, and every other category waiting on the shelf.
    func laptopLayout() -> DisplayLayout {
        let enabled = enabledLanes
        guard let first = enabled.first else { return displayLayout(kind: .standard) }
        let main = enabled.contains(.browser) ? Lane.browser : first
        var side = [Lane.terminal, .messaging].filter { enabled.contains($0) && $0 != main }
        for lane in enabled where side.count < 2 && lane != main && !side.contains(lane) { side.append(lane) }
        var rects: [String: ZoneRect] = [:]
        if side.isEmpty {
            rects[main.rawValue] = ZoneRect(CGRect(x: 0, y: 0, width: 1, height: 1))
        } else {
            rects[main.rawValue] = ZoneRect(CGRect(x: 0, y: 0, width: 0.6, height: 1))
            if side.count == 1 { rects[side[0].rawValue] = ZoneRect(CGRect(x: 0.6, y: 0, width: 0.4, height: 1)) }
            else {
                rects[side[0].rawValue] = ZoneRect(CGRect(x: 0.6, y: 0, width: 0.4, height: 0.55))
                rects[side[1].rawValue] = ZoneRect(CGRect(x: 0.6, y: 0.55, width: 0.4, height: 0.45))
            }
        }
        let kept = Set([main] + side)
        var layout = displayLayout(kind: .standard)
        layout.customRects = rects
        layout.shelvedLanes = Array(Set(shelvedLanes + enabled.filter { !kept.contains($0) }.map(\.rawValue))).sorted()
        layout.showMediaShelf = kept.contains(.media)
        for lane in kept { layout.capacities[lane.rawValue] = 1 }
        layout.useCustomGrid = true
        layout.stripPositions = [:]
        return layout
    }
    // Moves the grid to another display and keeps the one it leaves. A display seen
    // before gets its own grid back; a new laptop-shaped one gets the laptop layout;
    // a new wide one reuses a wide grid. Returns true when the grid changed.
    @discardableResult mutating func switchDisplay(to key: String, kind: DisplayKind, fresh: Bool = false) -> Bool {
        guard let current = activeDisplayKey else {
            // First run with per-display grids: the grid in use belongs to this display,
            // except that a brand-new install on a laptop starts from the laptop layout.
            let changed = fresh && kind == .standard
            if changed { apply(laptopLayout()) }
            activeDisplayKey = key
            displayLayouts[key] = displayLayout(kind: kind)
            return changed
        }
        guard current != key else { return false }
        displayLayouts[current] = displayLayout(kind: displayLayouts[current]?.kind ?? (kind == .wide ? .standard : .wide))
        let next = displayLayouts[key]
            ?? (kind == .standard ? laptopLayout() : displayLayouts.values.first { $0.kind == .wide } ?? displayLayout(kind: .wide))
        apply(next)
        activeDisplayKey = key
        displayLayouts[key] = next
        return true
    }
}

// What a new install of Lanes starts with: the setup it was built around.
// Terminal, Messaging and Browser side by side, a second Browser above a second
// Terminal on the right, expanding strips, and new windows opening in the center.
// Personal state (window assignments, tab names and order, saved presets,
// dragged strip spots) is never part of this.
extension Settings {
    // A new install starts with Browser filling the grid and every other category
    // on the shelf, so nothing appears that the person does not use. They drag in
    // the categories they want.
    static var firstRun: Settings {
        var s = Settings()
        s.customRects = [Lane.browser.rawValue: ZoneRect(CGRect(x: 0, y: 0, width: 1, height: 1))]
        s.capacities[Lane.browser.rawValue] = 1
        s.hiddenLanes = [Lane.terminal, .messaging, .simulator, .preview, .media].map(\.rawValue)
        s.shelvedLanes = [Lane.desktop.rawValue]
        s.showMediaShelf = false
        s.useCustomGrid = true
        s.stripPlacement = .onWindows
        s.windowStripStyle = .expanding
        s.windowStripScale = 0.8
        s.shortTabNames = true
        s.centerNewWindows = true
        s.autoArrange = false
        s.doubleRightCommand = true
        s.gap = 12
        return s
    }
}

// The first-run tour of the Lanes window: one highlighted part per step.
enum TourSpot: String { case permission, organize, restore, grid, categories, windows, preferences, openLanes }
struct TourStep: Equatable {
    let spot: TourSpot?   // nil: a step about the strips on the screen, shown with an illustration
    let title: String
    let body: String
}
enum TourGuide {
    static func steps(trusted: Bool) -> [TourStep] {
        var steps: [TourStep] = []
        if !trusted {
            steps.append(TourStep(spot: .permission, title: "Start here", body: "Lanes needs window control to arrange your windows. Click Open System Settings and switch Lanes on. You only do this once."))
        }
        steps += [
            TourStep(spot: .organize, title: "Organize", body: "Puts every open window into its category on your screen. From any app, tap the Command key to the right of the Space bar twice to do the same."),
            TourStep(spot: .restore, title: "Restore", body: "Changed your mind? Restore puts every window back where it was before Lanes moved it. Quitting Lanes does the same."),
            TourStep(spot: .grid, title: "Your screen, as a grid", body: "Each box is a category on your display. Drag a category up from the shelf below the grid to add it, drag a box to move it, or drag an edge to resize it. Nothing on your screen changes until you press Apply. Click a preset to preview a different arrangement, or save your own."),
            TourStep(spot: .categories, title: "Categories", body: "Each category holds one kind of window, like terminals or browsers. Click one to select it in the grid. To put a window or an app in a category, use Categories at the bottom of this window."),
            TourStep(spot: .windows, title: "Put anything anywhere", body: "On the left, windows and apps that have no place in your grid yet. On the right, every category and what is in it. Drag one onto a category, or use its menu. Switch between Windows and Apps at the top."),
            TourStep(spot: nil, title: "Strips on your screen", body: "Each category with two or more windows gets a small strip on its top edge. Hover it to see every window by name, scroll on it to switch, and drag its ≡ handle to move it."),
            TourStep(spot: .preferences, title: "Make it yours", body: "Strip style, where new windows open, Open at login and more are in Preferences."),
            TourStep(spot: .openLanes, title: "Open Lanes any time", body: "Lanes lives in the menu bar at the top of your screen: click its icon. Or hold Control, Option and Command (the three keys left of the Space bar) and press Space, from any app. Want it in the Dock too? Drag Lanes from your Applications folder into the Dock. Take this tour again from the menu bar icon."),
        ]
        return steps
    }
}

// The Categories section mirrors your grid: categories that share a vertical
// band of the screen form one column, left to right, each column top to bottom.
enum GridColumns {
    static func columns(rects: [String: ZoneRect], lanes: [Lane]) -> [[Lane]] {
        let placed = lanes.compactMap { lane in rects[lane.rawValue].map { (lane, $0.cgRect) } }.sorted { $0.1.minX < $1.1.minX }
        var columns: [(range: ClosedRange<Double>, items: [(Lane, CGRect)])] = []
        for (lane, r) in placed {
            let span = Double(r.minX)...Double(r.maxX)
            if let i = columns.firstIndex(where: { c in
                let overlap = min(c.range.upperBound, span.upperBound) - max(c.range.lowerBound, span.lowerBound)
                return overlap > 0.5 * min(c.range.upperBound - c.range.lowerBound, span.upperBound - span.lowerBound)
            }) {
                columns[i].items.append((lane, r))
                columns[i].range = min(columns[i].range.lowerBound, span.lowerBound)...max(columns[i].range.upperBound, span.upperBound)
            } else {
                columns.append((span, [(lane, r)]))
            }
        }
        return columns.sorted { $0.range.lowerBound < $1.range.lowerBound }
            .map { $0.items.sorted { abs($0.1.minY - $1.1.minY) > 0.001 ? $0.1.minY < $1.1.minY : $0.1.minX < $1.1.minX }.map(\.0) }
    }
}

enum TileMembership {
    // The category whose tile a window fills: most of the tile is covered and
    // most of the window sits inside it. Floating windows belong to none.
    static func category(of frame: CGRect, tiles: [(lane: Lane, tile: CGRect)]) -> Lane? {
        let area = frame.width * frame.height
        guard area > 0 else { return nil }
        var best: (lane: Lane, shared: Double)?
        for (lane, tile) in tiles {
            let overlap = frame.intersection(tile)
            guard !overlap.isNull else { continue }
            let shared = overlap.width * overlap.height
            guard shared >= tile.width * tile.height * 0.6, shared >= area * 0.7 else { continue }
            if shared > (best?.shared ?? 0) { best = (lane, shared) }
        }
        return best?.lane
    }
}

enum StrayWindow {
    // A window outside every category covers the grid when at least a quarter
    // of it sits on category regions.
    static func coversGrid(_ frame: CGRect, regions: [CGRect]) -> Bool {
        let area = frame.width * frame.height
        guard area > 0 else { return false }
        let covered = regions.reduce(0.0) { total, region in
            let overlap = frame.intersection(region)
            return total + (overlap.isNull ? 0 : overlap.width * overlap.height)
        }
        return covered >= area * 0.25
    }
}

enum NewWindowCenter {
    // The app's own size, shrunk to fit the display, centered on it.
    static func frame(for size: CGSize, in screen: CGRect, gap: Double) -> CGRect {
        let room = screen.insetBy(dx: gap, dy: gap)
        let width = min(size.width, room.width), height = min(size.height, room.height)
        return CGRect(x: room.midX - width / 2, y: room.midY - height / 2, width: width, height: height).integral
    }
}

enum StripPlacement: String, Codable, CaseIterable, Identifiable {
    case onWindows, aboveWindows
    var id: String { rawValue }
    var title: String { self == .onWindows ? "On the windows" : "Above the windows" }
}

// A moved strip's center, as a fraction of its category region. Values outside
// 0...1 are allowed so a strip can sit beside its region.
struct StripPosition: Codable, Equatable {
    var x: Double
    var y: Double
}

// Screen coordinates with the origin at the top left, like lane frames.
enum StripPlacementGeometry {
    // Strips keep clear of the display's sides so the last tab is easy to hit.
    static let edgeMargin = 20.0
    static func frame(size: CGSize, region: CGRect, bounds: CGRect, saved: StripPosition?) -> CGRect {
        let bounds = bounds.insetBy(dx: edgeMargin, dy: 0)
        let center = saved.map { CGPoint(x: region.minX + $0.x * region.width, y: region.minY + $0.y * region.height) }
            ?? CGPoint(x: region.midX, y: region.minY + size.height / 2)
        var frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        frame.origin.x = max(bounds.minX, min(frame.minX, bounds.maxX - frame.width))
        frame.origin.y = max(bounds.minY, min(frame.minY, bounds.maxY - frame.height))
        return frame
    }
    // An expanding strip grows to the right from where it rests, so the name
    // and pane chooser under the mouse never move. Shifts left only at the
    // display's edge.
    static func grown(rest: CGRect, size: CGSize, bounds: CGRect) -> CGRect {
        let bounds = bounds.insetBy(dx: edgeMargin, dy: 0)
        var frame = CGRect(x: rest.minX, y: rest.minY, width: size.width, height: size.height)
        if frame.maxX > bounds.maxX { frame.origin.x = max(bounds.minX, bounds.maxX - frame.width) }
        return frame
    }
    static func position(of frame: CGRect, in region: CGRect) -> StripPosition {
        StripPosition(x: (frame.midX - region.minX) / max(1, region.width), y: (frame.midY - region.minY) / max(1, region.height))
    }
}

struct SavedGridLayout: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var rects: [String: ZoneRect]
    var capacities: [String: Int]
    var lanes: [String]
    var gap: Double
    var categories: [CustomCategory]
    var categoryNames: [String: String]
    var windowCategories: [String: String]
}

struct Settings: Codable {
    var savedLayouts: [SavedGridLayout] = []
    var previousLayout: SavedGridLayout?
    var template: Template = .build
    var gap: Double = 12
    var capacities: [String: Int] = Dictionary(uniqueKeysWithValues: Lane.allCases.map { ($0.rawValue, $0.defaultCapacity) })
    var appRules: [String: String] = [:]
    var screenID: UInt32 = 0
    var splits: [Double] = [0.23, 0.42, 0.77, 0.56]
    var autoArrange: Bool = false
    var centerNewWindows = false
    var onlyTargetScreen: Bool = true
    var showLaneControls: Bool = true
    var shortTabNames = true
    var hasSeenTour = false
    var displayLayouts: [String: DisplayLayout] = [:]
    var placedWindows: [String] = []
    var activeDisplayKey: String?
    var stripPlacement: StripPlacement = .onWindows
    var stripPositions: [String: StripPosition] = [:]
    var windowStripStyle: WindowStripStyle = .compact
    var windowStripScale = 1.0
    var categoryStripStyles: [String: String] = [:]
    var useCustomGrid = false
    var windowCategories: [String: String] = [:]
    var windowLabels: [String: String] = [:]
    var windowOrder: [String: [String]] = [:]
    var showMediaShelf: Bool = true
    var placements: [String: String] = [:]
    var hiddenLanes: [String] = [Lane.browser.rawValue]
    var shelvedLanes: [String] = []
    var customRects: [String: ZoneRect] = [:]
    var customCategories: [CustomCategory] = []
    var categoryNames: [String: String] = [:]
    var snapToGrid = true
    var doubleRightCommand = true
    init() {}
    enum CodingKeys: String, CodingKey { case savedLayouts, previousLayout, template, gap, capacities, appRules, screenID, splits, autoArrange, centerNewWindows, onlyTargetScreen, showLaneControls, shortTabNames, hasSeenTour, displayLayouts, activeDisplayKey, placedWindows, stripPlacement, stripPositions, windowStripStyle, windowStripScale, categoryStripStyles, useCustomGrid, windowCategories, windowLabels, windowOrder, showMediaShelf, placements, hiddenLanes, shelvedLanes, customRects, snapToGrid, doubleRightCommand, customCategories, categoryNames }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        savedLayouts = try c.decodeIfPresent([SavedGridLayout].self, forKey: .savedLayouts) ?? []
        previousLayout = try c.decodeIfPresent(SavedGridLayout.self, forKey: .previousLayout)
        template = try c.decodeIfPresent(Template.self, forKey: .template) ?? .build
        gap = min(28, max(4, try c.decodeIfPresent(Double.self, forKey: .gap) ?? 12))
        capacities = try c.decodeIfPresent([String: Int].self, forKey: .capacities) ?? capacities
        appRules = try c.decodeIfPresent([String: String].self, forKey: .appRules) ?? [:]
        screenID = try c.decodeIfPresent(UInt32.self, forKey: .screenID) ?? 0
        let decoded = try c.decodeIfPresent([Double].self, forKey: .splits) ?? splits
        if decoded.count == 4, decoded.allSatisfy({ $0.isFinite }), decoded[0] >= 0.10, decoded[1] - decoded[0] >= 0.10, decoded[2] - decoded[1] >= 0.10, decoded[2] <= 0.90, decoded[3] >= 0.20, decoded[3] <= 0.80 { splits = decoded }
        autoArrange = try c.decodeIfPresent(Bool.self, forKey: .autoArrange) ?? false
        centerNewWindows = (try? c.decode(Bool.self, forKey: .centerNewWindows)) ?? !autoArrange
        onlyTargetScreen = try c.decodeIfPresent(Bool.self, forKey: .onlyTargetScreen) ?? true
        showLaneControls = try c.decodeIfPresent(Bool.self, forKey: .showLaneControls) ?? true
        shortTabNames = (try? c.decode(Bool.self, forKey: .shortTabNames)) ?? true
        hasSeenTour = (try? c.decode(Bool.self, forKey: .hasSeenTour)) ?? false
        displayLayouts = (try? c.decode([String: DisplayLayout].self, forKey: .displayLayouts)) ?? [:]
        activeDisplayKey = try? c.decode(String.self, forKey: .activeDisplayKey)
        placedWindows = (try? c.decode([String].self, forKey: .placedWindows)) ?? []
        stripPlacement = (try? c.decode(StripPlacement.self, forKey: .stripPlacement)) ?? .onWindows
        stripPositions = ((try? c.decode([String: StripPosition].self, forKey: .stripPositions)) ?? [:]).filter { $0.value.x.isFinite && $0.value.y.isFinite }
        windowStripStyle = (try? c.decode(WindowStripStyle.self, forKey: .windowStripStyle)) ?? .compact
        let stripScale = try c.decodeIfPresent(Double.self, forKey: .windowStripScale) ?? 1
        windowStripScale = min(1.5, max(0.8, stripScale.isFinite ? stripScale : 1))
        categoryStripStyles = try c.decodeIfPresent([String: String].self, forKey: .categoryStripStyles) ?? [:]
        windowCategories = try c.decodeIfPresent([String: String].self, forKey: .windowCategories) ?? [:]
        windowLabels = try c.decodeIfPresent([String: String].self, forKey: .windowLabels) ?? [:]
        windowOrder = try c.decodeIfPresent([String: [String]].self, forKey: .windowOrder) ?? [:]
        showMediaShelf = try c.decodeIfPresent(Bool.self, forKey: .showMediaShelf) ?? true
        placements = try c.decodeIfPresent([String: String].self, forKey: .placements) ?? [:]
        hiddenLanes = try c.decodeIfPresent([String].self, forKey: .hiddenLanes) ?? []
        // Older saved grids have no Browser region. Keep their geometry until
        // Organize discovers browsers or the user restores the new category.
        if capacities[Lane.browser.rawValue] == nil && !hiddenLanes.contains(Lane.browser.rawValue) { hiddenLanes.append(Lane.browser.rawValue) }
        shelvedLanes = try c.decodeIfPresent([String].self, forKey: .shelvedLanes) ?? []
        customCategories = try c.decodeIfPresent([CustomCategory].self, forKey: .customCategories) ?? []
        var seenIDs: Set<String> = []
        customCategories = customCategories.filter { Lane(rawValue: $0.id)?.isCustom == true && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seenIDs.insert($0.id).inserted }
        categoryNames = try c.decodeIfPresent([String: String].self, forKey: .categoryNames) ?? [:]
        if enabledLanes.isEmpty { hiddenLanes.removeAll(); shelvedLanes.removeAll() }
        customRects = try c.decodeIfPresent([String: ZoneRect].self, forKey: .customRects) ?? [:]
        useCustomGrid = try c.decodeIfPresent(Bool.self, forKey: .useCustomGrid) ?? !customRects.isEmpty
        snapToGrid = try c.decodeIfPresent(Bool.self, forKey: .snapToGrid) ?? true
        doubleRightCommand = try c.decodeIfPresent(Bool.self, forKey: .doubleRightCommand) ?? true
        if !customRects.isEmpty && !GridGeometry.valid(customRects, lanes: enabledLanes) { customRects = [:] }
    }
    var availableLanes: [Lane] { Lane.allCases + customCategories.map(\.lane) }
    var newWindowPlacement: NewWindowPlacement {
        get { autoArrange ? .category : centerNewWindows ? .center : .leave }
        set { autoArrange = newValue == .category; centerNewWindows = newValue == .center }
    }
    var stripReservesSpace: Bool { showLaneControls && stripPlacement == .aboveWindows }
    func name(_ lane: Lane) -> String { categoryNames[lane.rawValue] ?? customCategories.first(where: { $0.id == lane.rawValue })?.name ?? lane.title }
    var enabledLanes: [Lane] { availableLanes.filter { ($0 != .media || showMediaShelf) && !hiddenLanes.contains($0.rawValue) && !shelvedLanes.contains($0.rawValue) } }
    func unitRect(for lane: Lane) -> CGRect {
        let active = enabledLanes
        guard active.contains(lane) else { return .zero }
        if let rect = customRects[lane.rawValue] { return rect.cgRect }
        if !customCategories.isEmpty || active.contains(.browser) { return Layout.reflow(index: active.firstIndex(of: lane)!, count: active.count) }
        let fullCount = showMediaShelf ? 6 : 5
        if active.count == fullCount { return template.rect(for: slot(for: lane), splits: splits, includeMedia: showMediaShelf) }
        let ordered = active.sorted {
            let a = template.rect(for: slot(for: $0), splits: splits, includeMedia: showMediaShelf)
            let b = template.rect(for: slot(for: $1), splits: splits, includeMedia: showMediaShelf)
            if abs(a.midX - b.midX) > 0.001 { return a.midX < b.midX }
            return a.minY < b.minY
        }
        return Layout.reflow(index: ordered.firstIndex(of: lane)!, count: ordered.count)
    }
    func slot(for lane: Lane) -> Lane { LaneArrangement.normalized(placements, includeMedia: showMediaShelf)[lane] ?? lane }
    func capacity(_ lane: Lane) -> Int { min(4, max(1, capacities[lane.rawValue] ?? lane.defaultCapacity)) }
    func stripStyle(_ lane: Lane) -> WindowStripStyle {
        if categoryStripStyles[lane.rawValue] == "dots" { return .compact }
        return categoryStripStyles[lane.rawValue].flatMap(WindowStripStyle.init(rawValue:)) ?? windowStripStyle
    }
}

struct LaneArrangement {
    static func normalized(_ saved: [String: String], includeMedia: Bool) -> [Lane: Lane] {
        let lanes = Lane.legacyCases.filter { $0 != .media || includeMedia }
        let allowed = Set(lanes)
        var used: Set<Lane> = []
        var result: [Lane: Lane] = [:]
        for lane in lanes {
            if let raw = saved[lane.rawValue], let slot = Lane(rawValue: raw), allowed.contains(slot), !used.contains(slot) {
                result[lane] = slot; used.insert(slot)
            }
        }
        for lane in lanes where result[lane] == nil {
            let slot = !used.contains(lane) ? lane : lanes.first(where: { !used.contains($0) })!
            result[lane] = slot; used.insert(slot)
        }
        return result
    }
    static func swapped(_ saved: [String: String], source: Lane, target: Lane, includeMedia: Bool) -> [String: String] {
        var normalized = normalized(saved, includeMedia: includeMedia)
        guard let sourceSlot = normalized[source], let targetSlot = normalized[target] else { return saved }
        normalized[source] = targetSlot; normalized[target] = sourceSlot
        return Dictionary(uniqueKeysWithValues: normalized.map { ($0.key.rawValue, $0.value.rawValue) })
    }
}

struct Layout {
    struct StackPlan {
        var foregroundIDs: [String]
        var frames: [String: CGRect]
        var raiseOrder: [String]
    }
    static func stack(ids: [String], page: Int, capacity: Int, in frame: CGRect, gap: Double, lane: Lane, presentationOnly: Bool = false) -> StackPlan {
        let foreground = Array(ids[pageIndices(total: ids.count, capacity: capacity, page: page)])
        return stack(ids: ids, foreground: foreground, in: frame, gap: gap, lane: lane, presentationOnly: presentationOnly)
    }
    static func stack(ids: [String], foreground: [String], in frame: CGRect, gap: Double, lane: Lane, presentationOnly: Bool = false, onlyIDs: Set<String>? = nil, slotCount: Int? = nil) -> StackPlan {
        let tiles = tiles(in: frame, count: max(foreground.count, slotCount ?? foreground.count), gap: gap, lane: lane)
        guard !tiles.isEmpty else { return StackPlan(foregroundIDs: [], frames: [:], raiseOrder: []) }
        var placements: [String: CGRect] = [:]
        let valid = Set(ids)
        let selected = foreground.filter { valid.contains($0) }
        let touched = (presentationOnly ? selected : ids).filter { onlyIDs?.contains($0) ?? true }
        for (index, id) in touched.enumerated() { placements[id] = tiles[foreground.firstIndex(of: id) ?? (index % tiles.count)] }
        return StackPlan(foregroundIDs: selected, frames: placements, raiseOrder: touched.filter { !selected.contains($0) } + selected.filter { touched.contains($0) })
    }
    static func reflow(index: Int, count: Int) -> CGRect {
        switch count {
        case 1: return CGRect(x: 0, y: 0, width: 1, height: 1)
        case 2: return index == 0 ? CGRect(x: 0, y: 0, width: 0.65, height: 1) : CGRect(x: 0.65, y: 0, width: 0.35, height: 1)
        case 3:
            let widths = [0.30, 0.45, 0.25]
            return CGRect(x: widths.prefix(index).reduce(0, +), y: 0, width: widths[index], height: 1)
        case 4:
            switch index {
            case 0: return CGRect(x: 0, y: 0, width: 0.30, height: 1)
            case 1: return CGRect(x: 0.30, y: 0, width: 0.40, height: 1)
            case 2: return CGRect(x: 0.70, y: 0, width: 0.30, height: 0.65)
            default: return CGRect(x: 0.70, y: 0.65, width: 0.30, height: 0.35)
            }
        case 5:
            switch index {
            case 0: return CGRect(x: 0, y: 0, width: 0.22, height: 1)
            case 1: return CGRect(x: 0.22, y: 0, width: 0.22, height: 1)
            case 2: return CGRect(x: 0.44, y: 0, width: 0.32, height: 1)
            case 3: return CGRect(x: 0.76, y: 0, width: 0.24, height: 0.70)
            default: return CGRect(x: 0.76, y: 0.70, width: 0.24, height: 0.30)
            }
        default:
            guard count > 0, index >= 0, index < count else { return .zero }
            let columns = count <= 9 ? 3 : 4
            let rows = Int(ceil(Double(count) / Double(columns)))
            let row = index / columns, column = index % columns
            let onRow = min(columns, count - row * columns)
            return CGRect(x: Double(column) / Double(onRow), y: Double(row) / Double(rows), width: 1 / Double(onRow), height: 1 / Double(rows))
        }
    }
    static func frame(unit: CGRect, in screen: CGRect, gap: Double) -> CGRect {
        let inset = CGFloat(gap / 2)
        // Half-gap on each shared boundary, a full gap at the outside edge.
        let usable = screen.insetBy(dx: inset, dy: inset)
        return CGRect(x: usable.minX + unit.minX * usable.width,
                      y: usable.minY + unit.minY * usable.height,
                      width: unit.width * usable.width,
                      height: unit.height * usable.height).insetBy(dx: inset, dy: inset).integral
    }
    static func tiles(in frame: CGRect, count: Int, gap: Double, lane: Lane) -> [CGRect] {
        guard count > 0 else { return [] }
        let columns: Int
        if count == 1 { columns = 1 }
        else if lane == .browser && count == 2 { columns = 2 }
        else if lane == .simulator { columns = frame.width > frame.height ? count : 1 }
        else { columns = count > 2 ? 2 : (frame.width / frame.height > 1.45 ? 2 : 1) }
        let rows = Int(ceil(Double(count) / Double(columns)))
        let width = (frame.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
        let height = (frame.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
        return (0..<count).map { i in
            CGRect(x: frame.minX + CGFloat(i % columns) * (width + gap),
                   y: frame.minY + CGFloat(i / columns) * (height + gap),
                   width: width, height: height).integral
        }
    }
    static func pickerIndices(total: Int, active: Int, limit: Int) -> Range<Int> {
        guard total > 0, limit > 0 else { return 0..<0 }
        let count = min(total, limit)
        let start = max(0, min(total - count, active - count / 2))
        return start..<(start + count)
    }
    static func nextIndex(total: Int, current: Int?, delta: Int) -> Int {
        guard total > 0 else { return 0 }
        guard let current else { return delta < 0 ? total - 1 : 0 }
        return ((current + delta) % total + total) % total
    }
    static func organizingIDs(_ ids: [String], preferredID: String?) -> [String] {
        guard let preferredID, let index = ids.firstIndex(of: preferredID) else { return ids }
        return GridGeometry.rotatedIDs(ids, startingAt: index)
    }
    static func adjust(frame: CGRect, bounds: CGRect, dx: CGFloat, dy: CGFloat, resize: Bool) -> CGRect {
        var result = frame
        if resize {
            result.size.width = max(min(160, bounds.width), min(bounds.width, frame.width + dx))
            result.size.height = max(min(100, bounds.height), min(bounds.height, frame.height + dy))
        } else {
            result.origin.x += dx; result.origin.y += dy
        }
        result.origin.x = max(bounds.minX, min(bounds.maxX - result.width, result.minX))
        result.origin.y = max(bounds.minY, min(bounds.maxY - result.height, result.minY))
        return result.integral
    }
    static func pageCount(total: Int, capacity: Int) -> Int { max(1, (total + max(1, capacity) - 1) / max(1, capacity)) }
    static func pageIndices(total: Int, capacity: Int, page: Int) -> Range<Int> {
        let size = max(1, capacity)
        let safePage = max(0, min(page, pageCount(total: total, capacity: size) - 1))
        let start = min(total, safePage * size)
        return start..<min(total, start + size)
    }
}

struct WindowSlots {
    static func normalized(_ saved: [String], ids: [String], capacity: Int) -> [String] {
        var seen: Set<String> = []
        let valid = Set(ids)
        let count = max(1, capacity)
        var slots: [String?] = (0..<count).map { index in
            guard saved.indices.contains(index), valid.contains(saved[index]), seen.insert(saved[index]).inserted else { return nil }
            return saved[index]
        }
        var remaining = ids.filter { !seen.contains($0) }.makeIterator()
        for index in slots.indices where slots[index] == nil { slots[index] = remaining.next() }
        return slots.map { $0 ?? "" }
    }
    static func replacing(_ slots: [String], with id: String, at index: Int) -> [String] {
        guard !slots.isEmpty, !slots.contains(id) else { return slots }
        var result = slots; result[max(0, min(slots.count - 1, index))] = id; return result
    }
    static func nextID(ids: [String], slots: [String], slot: Int, delta: Int) -> String? {
        guard !slots.isEmpty else { return ids.first }
        let index = max(0, min(slots.count - 1, slot)), current = slots[index]
        let peers = Set(slots.enumerated().filter { $0.offset != index }.map(\.element))
        let candidates = ids.filter { !peers.contains($0) }
        guard !candidates.isEmpty else { return current }
        return candidates[Layout.nextIndex(total: candidates.count, current: candidates.firstIndex(of: current), delta: delta)]
    }
    static func reordered(_ ids: [String], source: String, before target: String, after: Bool = false) -> [String] {
        guard source != target, ids.contains(source), ids.contains(target) else { return ids }
        var result = ids.filter { $0 != source }
        result.insert(source, at: result.firstIndex(of: target)! + (after ? 1 : 0)); return result
    }
}

struct Classifier {
    static func isCompactPlayer(title: String) -> Bool {
        let text = title.lowercased()
        return ["picture-in-picture", "picture in picture", "pip player", "mini player", "miniplayer"].contains(where: text.contains)
    }
    static func lane(bundleID: String, appName: String, title: String, rules: [String: String]) -> Lane {
        if let rule = rules[bundleID], let lane = Lane(rawValue: rule) { return lane }
        let app = (bundleID + " " + appName).lowercased()
        if isCompactPlayer(title: title) || app.contains("com.spotify.client") { return .media }
        if ["ghostty", "iterm", "com.apple.terminal", "warp", "wezterm", "alacritty", "kitty", "hyper"].contains(where: app.contains) { return .terminal }
        if ["iphonesimulator", "simulator", "emulator", "screencontinuity", "genymotion"].contains(where: app.contains) { return .simulator }
        if ["telegram", "whatsapp", "discord", "mobilesms", "slack", "larksuite", "mail", "signal", "messenger", "mobilephone"].contains(where: app.contains) { return .messaging }
        if ["quicktime", "vlc", "iina", "com.apple.preview", "finalcut", "davinci", "capcut", "premiere", "aftereffects", "imovie", "lumafusion", "motionapp", "spotify"].contains(where: app.contains) { return .preview }
        if ["browser", "chrome", "safari", "firefox", "orion", "microsoft.edgemac", "brave", "vivaldi", "operasoftware", "zen-browser"].contains(where: app.contains) || appName.lowercased() == "arc" { return .browser }
        return .desktop
    }
}

// Normalized display coordinates, with the origin at the top left.
struct ZoneRect: Codable, Equatable {
    var x: Double, y: Double, width: Double, height: Double
    init(_ rect: CGRect) { x = rect.minX; y = rect.minY; width = rect.width; height = rect.height }
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
struct GridGeometry {
    static func valid(_ rects: [String: ZoneRect], lanes: [Lane]) -> Bool {
        let values = lanes.compactMap { rects[$0.rawValue]?.cgRect }
        guard values.count == lanes.count else { return false }
        for (i, r) in values.enumerated() {
            guard [r.minX, r.minY, r.width, r.height].allSatisfy({ $0.isFinite }),
                  r.width >= 0.04 - 0.000001, r.height >= 0.06 - 0.000001, r.minX >= -0.000001, r.minY >= -0.000001,
                  r.maxX <= 1.000001, r.maxY <= 1.000001 else { return false }
            for other in values.dropFirst(i + 1) {
                let overlap = r.intersection(other)
                if !overlap.isNull && overlap.width > 0.000001 && overlap.height > 0.000001 { return false }
            }
        }
        return true
    }
    static func edited(_ original: CGRect, dx: Double, dy: Double, resize: Bool, snap: Bool) -> CGRect {
        func quantize(_ n: Double, _ steps: Double) -> Double { snap ? (n * steps).rounded() / steps : n }
        var rect = original
        if resize {
            let right = min(1, max(original.minX + 0.04, quantize(original.maxX + dx, 32)))
            let bottom = min(1, max(original.minY + 0.06, quantize(original.maxY + dy, 16)))
            rect.size = CGSize(width: right - rect.minX, height: bottom - rect.minY)
        } else {
            rect.origin.x = min(1 - rect.width, max(0, quantize(original.minX + dx, 32)))
            rect.origin.y = min(1 - rect.height, max(0, quantize(original.minY + dy, 16)))
        }
        return rect
    }
    static func resizing(_ rects: [String: ZoneRect], lane: Lane, edge: ResizeEdge, dx: Double, dy: Double, snap: Bool) -> [String: ZoneRect] {
        if edge == .bottomRight {
            let widened = resizing(rects, lane: lane, edge: .right, dx: dx, dy: 0, snap: snap)
            return resizing(widened, lane: lane, edge: .bottom, dx: 0, dy: dy, snap: snap)
        }
        guard let selected = rects[lane.rawValue]?.cgRect else { return rects }
        let vertical = edge == .left || edge == .right
        func lower(_ r: CGRect) -> Double { vertical ? r.minX : r.minY }
        func upper(_ r: CGRect) -> Double { vertical ? r.maxX : r.maxY }
        func crossLower(_ r: CGRect) -> Double { vertical ? r.minY : r.minX }
        func crossUpper(_ r: CGRect) -> Double { vertical ? r.maxY : r.maxX }
        let line = (edge == .left || edge == .top) ? lower(selected) : upper(selected)
        var spanLow = crossLower(selected), spanHigh = crossUpper(selected)
        var connected = Set<String>()
        // Extend through T junctions: a full-height neighbor joins the upper and
        // lower categories into the same shared divider, without creating gaps.
        var expanded = true
        while expanded {
            expanded = false
            for (key, zone) in rects where !connected.contains(key) {
                let r = zone.cgRect
                let touches = abs(lower(r) - line) < 0.000001 || abs(upper(r) - line) < 0.000001
                if touches && min(spanHigh, crossUpper(r)) - max(spanLow, crossLower(r)) > 0.000001 {
                    connected.insert(key); spanLow = min(spanLow, crossLower(r)); spanHigh = max(spanHigh, crossUpper(r)); expanded = true
                }
            }
        }
        let minimum = vertical ? 0.04 : 0.06
        var low = 0.0, high = 1.0
        for key in connected {
            let r = rects[key]!.cgRect
            if abs(upper(r) - line) < 0.000001 { low = max(low, lower(r) + minimum) }
            if abs(lower(r) - line) < 0.000001 { high = min(high, upper(r) - minimum) }
        }
        guard low <= high else { return rects }
        let delta = vertical ? dx : dy
        let steps = vertical ? 32.0 : 16.0
        let target = line + delta
        let boundary = min(high, max(low, snap ? (target * steps).rounded() / steps : target))
        var result = rects
        for key in connected {
            var r = rects[key]!.cgRect
            let oldMax = upper(r)
            if abs(upper(r) - line) < 0.000001 {
                if vertical { r.size.width = boundary - r.minX } else { r.size.height = boundary - r.minY }
            } else if abs(lower(r) - line) < 0.000001 {
                if vertical { r.origin.x = boundary; r.size.width = oldMax - boundary }
                else { r.origin.y = boundary; r.size.height = oldMax - boundary }
            }
            result[key] = ZoneRect(r)
        }
        let lanes = rects.keys.compactMap { Lane(rawValue: $0) }
        if valid(result, lanes: lanes) { return result }
        // For custom layouts with a gap, stop at the last collision-free point.
        var best = rects, fractionLow = 0.0, fractionHigh = 1.0
        for _ in 0..<24 {
            let fraction = (fractionLow + fractionHigh) / 2
            var candidate = rects
            for key in connected {
                let original = rects[key]!, changed = result[key]!
                candidate[key] = ZoneRect(CGRect(x: original.x + (changed.x - original.x) * fraction,
                    y: original.y + (changed.y - original.y) * fraction,
                    width: original.width + (changed.width - original.width) * fraction,
                    height: original.height + (changed.height - original.height) * fraction))
            }
            if valid(candidate, lanes: lanes) { best = candidate; fractionLow = fraction }
            else { fractionHigh = fraction }
        }
        return best
    }
    // Where a category dropped in the grid editor ends up. A move that fits stays
    // put; dropped on another category, the two trade places; dropped on free space,
    // it fills that space. Only when none of these work is the move refused.
    enum SnapPlan: Equatable { case move(CGRect), swap(Lane), fit([String: ZoneRect]), none }
    static func snapPlan(_ lane: Lane, candidate: CGRect, at point: CGPoint, rects: [String: ZoneRect], lanes: [Lane]) -> SnapPlan {
        var trial = rects; trial[lane.rawValue] = ZoneRect(candidate)
        if valid(trial, lanes: lanes) { return .move(candidate) }
        if let target = lanes.first(where: { $0 != lane && (rects[$0.rawValue]?.cgRect.contains(point) ?? false) }) { return .swap(target) }
        var without = rects; without[lane.rawValue] = nil
        if let fitted = restoring(lane, rects: without, active: lanes.filter { $0 != lane }, at: point) { return .fit(fitted) }
        return .none
    }
    static func restoring(_ lane: Lane, rects: [String: ZoneRect], active: [Lane], at point: CGPoint? = nil) -> [String: ZoneRect]? {
        let existing = active.compactMap { rects[$0.rawValue]?.cgRect }
        let xs = Array(Set([0.0, 1.0] + existing.flatMap { [$0.minX, $0.maxX] })).sorted()
        let ys = Array(Set([0.0, 1.0] + existing.flatMap { [$0.minY, $0.maxY] })).sorted()
        var best: CGRect?
        // Prefer empty space left by deletion or resizing before splitting a neighbor.
        for i in 0..<(xs.count - 1) { for j in (i + 1)..<xs.count {
            for a in 0..<(ys.count - 1) { for b in (a + 1)..<ys.count {
                let rect = CGRect(x: xs[i], y: ys[a], width: xs[j] - xs[i], height: ys[b] - ys[a])
                guard rect.width >= 0.04, rect.height >= 0.06 else { continue }
                if let point, !rect.contains(point) { continue }
                var candidate = rects; candidate[lane.rawValue] = ZoneRect(rect)
                if valid(candidate, lanes: active + [lane]), rect.width * rect.height > (best.map { $0.width * $0.height } ?? 0) { best = rect }
            }}
        }}
        if let best { var result = rects; result[lane.rawValue] = ZoneRect(best); return result }
        let candidates = active.filter { guard let r = rects[$0.rawValue]?.cgRect else { return false }; return r.width >= 0.08 || r.height >= 0.12 }
        guard let largest = point.flatMap({ p in candidates.first { rects[$0.rawValue]!.cgRect.contains(p) } }) ?? candidates.max(by: { rects[$0.rawValue]!.width * rects[$0.rawValue]!.height < rects[$1.rawValue]!.width * rects[$1.rawValue]!.height }) else { return nil }
        var rect = rects[largest.rawValue]!.cgRect, new = rect
        if (lane == .media && rect.height >= 0.20) || rect.width < 0.08 {
            let fraction = lane == .media && rect.height >= 0.20 ? 0.7 : 0.5
            rect.size.height *= fraction; new.origin.y = rect.maxY; new.size.height *= (1 - fraction)
        } else {
            rect.size.width *= 0.5; new.origin.x = rect.maxX; new.size.width *= 0.5
        }
        if let point, rect.contains(point) { swap(&rect, &new) }
        var result = rects; result[largest.rawValue] = ZoneRect(rect); result[lane.rawValue] = ZoneRect(new)
        return valid(result, lanes: active + [lane]) ? result : nil
    }
    static func rotatedIDs(_ ids: [String], startingAt index: Int) -> [String] {
        guard !ids.isEmpty else { return [] }
        let offset = ((index % ids.count) + ids.count) % ids.count
        return Array(ids[offset...] + ids[..<offset])
    }
}
// Trigger only on two short, clean press/release taps. Any shortcut or other
// modifier cancels the sequence; Command remains available to every app.
struct DoubleCommandTap {
    private var downAt: Double?
    private var previousUp: Double?
    mutating func cancel() { downAt = nil; previousUp = nil }
    mutating func flags(keyCode: UInt16, commandDown: Bool, otherModifiers: Bool, time: Double) -> Bool {
        guard keyCode == 54, !otherModifiers else { cancel(); return false }
        if commandDown {
            if downAt == nil { downAt = time }
            return false
        }
        guard let start = downAt else { previousUp = nil; return false }
        downAt = nil
        guard time >= start, time - start <= 0.28 else { previousUp = nil; return false }
        if let previous = previousUp, start >= previous, time - previous <= 0.45 {
            previousUp = nil; return true
        }
        previousUp = time
        return false
    }
}

enum ResizeEdge: String, CaseIterable {
    case left, right, top, bottom, bottomRight
}

struct CategoryDeletionKey {
    static func shouldDelete(keyCode: UInt16, hasModifiers: Bool, gridSelected: Bool, isEditingText: Bool, boardIsKey: Bool) -> Bool {
        (keyCode == 51 || keyCode == 117) && !hasModifiers && gridSelected && !isEditingText && boardIsKey
    }
}

struct LaneScrollAccumulator {
    private var amount = 0.0
    private var lastTime = -Double.infinity
    private var lastEventTime = -Double.infinity
    mutating func consume(delta: Double, precise: Bool, time: Double, momentum: Bool = false) -> Int? {
        guard delta != 0 else { return nil }
        if time - lastEventTime > 0.35 || amount * delta < 0 { amount = 0 }
        lastEventTime = time
        amount += delta
        // Fingers switch every few points. A flick's momentum carries on more
        // slowly and fades out with the flick, so it cannot race past everything.
        let threshold = momentum ? 30.0 : precise ? 6.0 : 1.0
        guard abs(amount) >= threshold, time - lastTime >= (momentum ? 0.09 : 0.03) else { return nil }
        let direction = amount < 0 ? 1 : -1
        amount = 0; lastTime = time
        return direction
    }
}

struct AutoSortItem {
    let lane: Lane
    let count: Int
    var requiredSize: CGSize? = nil
    var isFocused = false
    var stripInset = 36.0
}
struct AutoSortPlan {
    let rects: [String: ZoneRect]
    let capacities: [String: Int]
}
struct AutoSorter {
    static func minimumSize(_ lane: Lane) -> CGSize {
        switch lane {
        case .terminal: return CGSize(width: 640, height: 300)
        case .simulator: return CGSize(width: 320, height: 600)
        case .preview: return CGSize(width: 900, height: 470)
        case .browser: return CGSize(width: 980, height: 600)
        case .desktop: return CGSize(width: 700, height: 400)
        case .messaging: return CGSize(width: 440, height: 500)
        case .media: return CGSize(width: 260, height: 180)
        default: return CGSize(width: 640, height: 400)
        }
    }
    static func minimumSize(_ item: AutoSortItem) -> CGSize {
        let base = minimumSize(item.lane)
        guard let required = item.requiredSize else { return base }
        return CGSize(width: max(base.width, required.width), height: max(base.height, required.height))
    }
    static func weight(_ item: AutoSortItem) -> Double {
        let base: Double
        switch item.lane { case .terminal: base = 1.4; case .simulator: base = 0.8; case .preview: base = 1.3; case .browser: base = 2.2; case .desktop: base = 1.6; case .messaging: base = 0.85; case .media: base = 0.4; default: base = 1.1 }
        let ideal = minimumSize(item.lane), required = minimumSize(item)
        let minimumAreaFactor = sqrt(Double(required.width * required.height / (ideal.width * ideal.height)))
        return base * (item.isFocused ? 1.3 : 1) * max(1, minimumAreaFactor) * (0.8 + 0.2 * sqrt(Double(min(6, max(1, item.count)))))
    }
    static func capacity(_ item: AutoSortItem, frame: CGRect, gap: Double) -> Int {
        let desired = item.lane == .terminal || item.lane == .simulator ? min(2, item.count) : 1
        let minimum = minimumSize(item)
        for n in stride(from: max(1, desired), through: 1, by: -1) {
            let tiles = Layout.tiles(in: frame, count: n, gap: gap, lane: item.lane)
            if tiles.allSatisfy({ $0.width >= minimum.width && $0.height >= minimum.height }) { return n }
        }
        return 1
    }
    static func plan(items input: [AutoSortItem], screen: CGRect, gap: Double) -> AutoSortPlan {
        let items = input.filter { $0.count > 0 }
        guard !items.isEmpty else { return AutoSortPlan(rects: [:], capacities: [:]) }
        // A bounded exhaustive search over column groups covers normal desktop
        // workloads. Larger category counts use the same scoring on balanced groups.
        let weights = items.map(weight)
        var bestScore = Double.infinity, bestRects: [String: ZoneRect] = [:], bestCapacities: [String: Int] = [:]
        func evaluate(_ groups: [Range<Int>]) {
            let totals = groups.map { weights[$0].reduce(0, +) }
            let widthWeights = totals.map { pow($0, 0.85) }
            let totalWidthWeight = widthWeights.reduce(0, +)
            var x = 0.0, rects: [String: ZoneRect] = [:], capacities: [String: Int] = [:]
            var score = Double(groups.count) * 0.025
            for (column, range) in groups.enumerated() {
                let width = widthWeights[column] / totalWidthWeight
                var y = 0.0
                for i in range {
                    let height = weights[i] / totals[column]
                    let unit = CGRect(x: x, y: y, width: width, height: height)
                    var frame = Layout.frame(unit: unit, in: screen, gap: gap)
                    frame.origin.y += items[i].stripInset; frame.size.height = max(80, frame.height - items[i].stripInset)
                    let count = capacity(items[i], frame: frame, gap: gap)
                    capacities[items[i].lane.rawValue] = count
                    let tile = Layout.tiles(in: frame, count: count, gap: gap, lane: items[i].lane).first ?? frame
                    let minimum = minimumSize(items[i])
                    let widthShortfall = max(0, minimum.width / max(1, tile.width) - 1)
                    let heightShortfall = max(0, minimum.height / max(1, tile.height) - 1)
                    let idealAspect = items[i].lane == .simulator ? 0.55 : items[i].lane == .messaging ? 0.85 : items[i].lane == .media ? 1.7 : 1.4
                    let aspectPenalty = pow(log(max(0.01, tile.width / max(1, tile.height)) / idealAspect), 2)
                    score += weights[i] * (12 * (widthShortfall * widthShortfall + heightShortfall * heightShortfall) + 0.45 * aspectPenalty)
                    rects[items[i].lane.rawValue] = ZoneRect(unit); y += height
                }
                x += width
            }
            if score < bestScore && GridGeometry.valid(rects, lanes: items.map(\.lane)) { bestScore = score; bestRects = rects; bestCapacities = capacities }
        }
        for columns in 1...min(5, items.count) {
            if items.count > 12 {
                var groups: [Range<Int>] = [], start = 0
                for column in 0..<columns {
                    let end = Int((Double(column + 1) * Double(items.count) / Double(columns)).rounded())
                    groups.append(start..<end); start = end
                }
                evaluate(groups); continue
            }
            func split(_ start: Int, _ remaining: Int, _ groups: [Range<Int>]) {
                if remaining == 1 { evaluate(groups + [start..<items.count]); return }
                for end in (start + 1)...(items.count - remaining + 1) { split(end, remaining - 1, groups + [start..<end]) }
            }
            split(0, columns, [])
        }
        if bestRects.isEmpty {
            bestRects = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.lane.rawValue, ZoneRect(Layout.reflow(index: $0.offset, count: items.count))) })
            bestCapacities = Dictionary(uniqueKeysWithValues: items.map { ($0.lane.rawValue, 1) })
        }
        return AutoSortPlan(rects: bestRects, capacities: bestCapacities)
    }
}

// Bare keys are scoped to the hovered strip; existing modified app shortcuts stay intact.
enum StripKeyAction: Equatable {
    case cycle(Int), select(Int)
    static let bindings: [(UInt16, StripKeyAction)] = [
        (123, .cycle(-1)), (124, .cycle(1)),
        (18, .select(0)), (19, .select(1)), (20, .select(2)), (21, .select(3)),
        (23, .select(4)), (22, .select(5)), (26, .select(6)), (28, .select(7)),
        (25, .select(8)), (29, .select(9))
    ]
    static func action(keyCode: UInt16, hasModifiers: Bool, hovering: Bool) -> StripKeyAction? {
        guard hovering, !hasModifiers else { return nil }
        return bindings.first { $0.0 == keyCode }?.1
    }
}
