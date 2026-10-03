import Foundation
import CoreGraphics

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError("FAIL: \(message)") }
}
let settings = Settings()
for template in Template.allCases {
    let rects = Lane.legacyCases.map { template.rect(for: $0, splits: settings.splits) }
    expect(abs(rects.reduce(0) { $0 + $1.width * $1.height } - 1) < 0.0001, "\(template): complete screen coverage")
    for (index, rect) in rects.enumerated() {
        expect(CGRect(x: 0, y: 0, width: 1, height: 1).contains(rect), "\(template): rect contained")
        for other in rects.dropFirst(index + 1) {
            let overlap = rect.intersection(other)
            expect(overlap.isNull || overlap.width < 0.001 || overlap.height < 0.001, "\(template): no overlapping lanes")
        }
    }
}
for screen in [CGRect(x: 0, y: 30, width: 5120, height: 1350), CGRect(x: -1920, y: -1080, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 2560, height: 660)] {
    for gap in [4.0, 12.0, 28.0] {
        for lane in Lane.legacyCases {
            let frame = Layout.frame(unit: settings.template.rect(for: lane, splits: settings.splits), in: screen, gap: gap)
            expect(screen.contains(frame), "lane in multi-display bounds")
            for count in 1...4 {
                let tiles = Layout.tiles(in: frame, count: count, gap: gap, lane: lane)
                expect(tiles.count == count, "correct tile count")
                for (index, tile) in tiles.enumerated() {
                    expect(tile.width > 0 && tile.height > 0, "positive tile dimensions")
                    expect(tile.minX >= frame.minX - 1 && tile.maxX <= frame.maxX + 1 && tile.minY >= frame.minY - 1 && tile.maxY <= frame.maxY + 1, "tile inside lane")
                    for other in tiles.dropFirst(index + 1) { expect(!tile.intersects(other), "tiles don't overlap") }
                }
            }
        }
    }
}
for total in 0...31 {
    for capacity in 1...4 {
        var visited: [Int] = []
        for page in 0..<Layout.pageCount(total: total, capacity: capacity) {
            let range = Layout.pageIndices(total: total, capacity: capacity, page: page)
            expect(range.count <= capacity, "capacity respected")
            visited += Array(range)
        }
        expect(visited == Array(0..<total), "every window appears exactly once")
        expect(Layout.pageIndices(total: total, capacity: capacity, page: 999).upperBound <= total, "stale page is clamped")
    }
}
let classification: [(String, String, String, Lane)] = [
    ("com.mitchellh.ghostty", "Ghostty", "zsh", .terminal),
    ("com.apple.iphonesimulator", "Simulator", "iPhone", .simulator),
    ("com.apple.ScreenContinuity", "iPhone Mirroring", "iPhone", .simulator),
    ("com.apple.QuickTimePlayerX", "QuickTime Player", "video.mov", .preview),
    ("company.thebrowser.Browser", "Arc", "Instagram", .browser),
    ("company.thebrowser.Browser", "Arc", "localhost:3000", .browser),
    ("com.larksuite.larkApp", "Lark", "Chat", .messaging),
    ("net.whatsapp.WhatsApp", "WhatsApp", "Chat", .messaging),
    ("com.apple.finder", "Finder", "Downloads", .desktop),
    ("com.openai.codex", "ChatGPT", "Lanes", .desktop)
]
for (bundle, name, title, expected) in classification {
    expect(Classifier.lane(bundleID: bundle, appName: name, title: title, rules: [:]) == expected, "classification for \(name)")
}
expect(Classifier.lane(bundleID: "company.thebrowser.Browser", appName: "Arc", title: "Instagram", rules: ["company.thebrowser.Browser": "desktop"]) == .desktop, "saved app rule overrides title heuristics")
let encoded = try JSONEncoder().encode(settings)
let decoded = try JSONDecoder().decode(Settings.self, from: encoded)
expect(decoded.splits == settings.splits && decoded.capacity(.terminal) == 2 && !decoded.autoArrange, "settings roundtrip and safe defaults")
for total in 1...12 {
    expect(Layout.nextIndex(total: total, current: nil, delta: 1) == 0, "first cycle selects first window")
    expect(Layout.nextIndex(total: total, current: nil, delta: -1) == total - 1, "first reverse cycle selects last window")
    for current in 0..<total {
        let next = Layout.nextIndex(total: total, current: current, delta: 1)
        expect(next >= 0 && next < total, "cycle remains in bounds")
        expect(Layout.nextIndex(total: total, current: next, delta: -1) == current, "window cycling is reversible")
    }
    expect(Layout.nextIndex(total: total, current: total - 1, delta: 1) == 0, "last window wraps to first")
}
let bounds = CGRect(x: -900, y: 30, width: 700, height: 600)
let original = CGRect(x: -860, y: 70, width: 400, height: 300)
for dx in [-999.0, -24, 0, 24, 999] {
    for dy in [-999.0, -24, 0, 24, 999] {
        let moved = Layout.adjust(frame: original, bounds: bounds, dx: dx, dy: dy, resize: false)
        expect(bounds.contains(moved) && moved.size == original.size, "nudging clamps to lane and preserves size")
        let resized = Layout.adjust(frame: original, bounds: bounds, dx: dx, dy: dy, resize: true)
        expect(bounds.contains(resized), "resizing remains in lane")
        expect(resized.width >= 160 && resized.height >= 100, "resizing maintains usable minimum dimensions")
    }
}
expect(Layout.adjust(frame: original, bounds: bounds, dx: 24, dy: 0, resize: false).minX == original.minX + 24, "24 pt nudge")
expect(Layout.adjust(frame: original, bounds: bounds, dx: -24, dy: 0, resize: true).width == original.width - 24, "24 pt resize")
let legacy = Data("{\"template\":\"studio\",\"gap\":18,\"appRules\":{\"com.google.Chrome\":\"desktop\"},\"capacities\":{\"messaging\":1}}".utf8)
let migrated = try JSONDecoder().decode(Settings.self, from: legacy)
expect(migrated.template == .studio && migrated.gap == 18 && migrated.capacity(.messaging) == 1, "upgrades preserve layout preferences")
expect(migrated.appRules["com.google.Chrome"] == "desktop", "upgrades preserve app rules")
expect(migrated.showLaneControls && migrated.showMediaShelf && migrated.capacity(.media) == 1, "new fields get safe defaults")
for template in Template.allCases {
    let rects = Lane.legacyCases.map { template.rect(for: $0, splits: settings.splits, includeMedia: false) }
    expect(abs(rects.reduce(0) { $0 + $1.width * $1.height } - 1) < 0.0001, "disabled media shelf preserves total layout area")
    expect(template.rect(for: .media, splits: settings.splits, includeMedia: false) == .zero, "disabled shelf takes no space")
}
expect(Classifier.lane(bundleID: "com.google.Chrome", appName: "Chrome", title: "Picture in Picture", rules: [:]) == .media, "Picture-in-Picture gets dedicated media shelf")
expect(Classifier.lane(bundleID: "com.spotify.client", appName: "Spotify", title: "Mini player", rules: [:]) == .media, "mini Spotify belongs to media shelf")
var arrangement: [String: String] = [:]
for source in Lane.legacyCases {
    for target in Lane.legacyCases {
        let before = LaneArrangement.normalized(arrangement, includeMedia: true)
        arrangement = LaneArrangement.swapped(arrangement, source: source, target: target, includeMedia: true)
        let after = LaneArrangement.normalized(arrangement, includeMedia: true)
        expect(Set(after.values).count == Lane.legacyCases.count, "every category keeps a unique grid slot after drag-and-drop")
        expect(after[source] == before[target] && after[target] == before[source], "drop swaps exactly the selected categories")
        let hidden = LaneArrangement.normalized(arrangement, includeMedia: false)
        expect(hidden.count == 5 && Set(hidden.values).count == 5 && !hidden.values.contains(.media), "disabling shelf leaves no invisible or duplicated categories")
    }
}
let repaired = LaneArrangement.normalized(["terminal": "desktop", "messaging": "desktop", "media": "invalid"], includeMedia: true)
expect(repaired.count == 6 && Set(repaired.values).count == 6, "invalid or duplicate saved positions are repaired")
for mask in 0..<63 {
    var reduced = Settings()
    reduced.hiddenLanes = Lane.legacyCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map { $0.element.rawValue }
    for template in Template.allCases {
        reduced.template = template
        let rects = reduced.enabledLanes.map { reduced.unitRect(for: $0) }
        expect(abs(rects.reduce(0) { $0 + $1.width * $1.height } - 1) < 0.0001, "deleting categories reflows to full display coverage")
        for (index, rect) in rects.enumerated() {
            expect(rect.width > 0 && rect.height > 0, "every remaining category has a usable region")
            for other in rects.dropFirst(index + 1) {
                let overlap = rect.intersection(other)
                expect(overlap.isNull || overlap.width < 0.001 || overlap.height < 0.001, "remaining categories don't overlap")
            }
        }
    }
}

for removed in Lane.legacyCases {
    var full = Settings()
    full.customRects = Dictionary(uniqueKeysWithValues: full.enabledLanes.map { ($0.rawValue, ZoneRect(full.unitRect(for: $0))) })
    let before = full.customRects
    full.hiddenLanes.append(removed.rawValue); full.customRects.removeValue(forKey: removed.rawValue)
    let restored = GridGeometry.restoring(removed, rects: full.customRects, active: full.enabledLanes)
    expect(restored != nil && GridGeometry.valid(restored!, lanes: Lane.legacyCases), "restored category occupies safe space")
    for lane in full.enabledLanes { expect(restored?[lane.rawValue] == before[lane.rawValue], "restoring a deleted category preserves all other custom zones") }
}
var noShelf = Settings(); noShelf.showMediaShelf = false
let noShelfRects = Dictionary(uniqueKeysWithValues: noShelf.enabledLanes.map { ($0.rawValue, ZoneRect(noShelf.unitRect(for: $0))) })
let shelfRestored = GridGeometry.restoring(.media, rects: noShelfRects, active: noShelf.enabledLanes)
expect(shelfRestored != nil && GridGeometry.valid(shelfRestored!, lanes: Lane.legacyCases), "adding shelf to a full layout splits one region without overlap")
// Arbitrary custom zones survive upgrades, while corrupt/overlapping maps recover safely.
var custom = Settings()
custom.customRects = Dictionary(uniqueKeysWithValues: custom.enabledLanes.map { ($0.rawValue, ZoneRect(custom.unitRect(for: $0))) })
expect(GridGeometry.valid(custom.customRects, lanes: custom.enabledLanes), "default zones are valid custom regions")
let savedCustom = try JSONEncoder().encode(custom)
let loadedCustom = try JSONDecoder().decode(Settings.self, from: savedCustom)
expect(loadedCustom.customRects == custom.customRects, "custom geometry round trips without losing precision")
let oldTerminal = custom.unitRect(for: .terminal)
var changed = custom.customRects
changed["terminal"] = ZoneRect(CGRect(x: 0, y: 0, width: 0.12, height: 0.75))
expect(GridGeometry.valid(changed, lanes: custom.enabledLanes), "shrinking a category leaves usable free space")
changed["terminal"] = ZoneRect(CGRect(x: 0, y: 0, width: 0.7, height: 0.75))
expect(!GridGeometry.valid(changed, lanes: custom.enabledLanes), "resizing into a neighbor is rejected")
custom.customRects = changed
let corruptCustom = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(custom))
expect(corruptCustom.customRects.isEmpty, "overlapping saved geometry falls back to a safe template")
changed["terminal"] = ZoneRect(CGRect(x: -0.1, y: 0, width: 0.1, height: 0.75))
expect(!GridGeometry.valid(changed, lanes: custom.enabledLanes), "off-display geometry is rejected")
let movable = CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.5)
for dx in [-3.0, -0.03, 0.019, 0.5, 3] {
    for dy in [-3.0, -0.03, 0.019, 0.5, 3] {
        for snap in [false, true] {
            let move = GridGeometry.edited(movable, dx: dx, dy: dy, resize: false, snap: snap)
            expect(CGRect(x: 0, y: 0, width: 1, height: 1).contains(move) && move.size == movable.size, "drag clamps to display and preserves category size")
            let resize = GridGeometry.edited(movable, dx: dx, dy: dy, resize: true, snap: snap)
            expect(resize.minX == movable.minX && resize.minY == movable.minY && resize.width >= 0.04 - 0.000001 && resize.height >= 0.06 - 0.000001 && resize.maxX <= 1 && resize.maxY <= 1, "corner resize maintains origin, minima, and bounds")
        }
    }
}
let freeDrag = GridGeometry.edited(movable, dx: 0.019, dy: 0.019, resize: false, snap: false)
expect(abs(freeDrag.minX - 0.269) < 0.000001, "free placement retains fine adjustments")
let snappedDrag = GridGeometry.edited(movable, dx: 0.019, dy: 0.019, resize: false, snap: true)
expect(snappedDrag.minX == 0.28125 && snappedDrag.minY == 0.25, "snapping follows a 32 by 16 grid")
for count in 1...12 {
    let ids = (0..<count).map { "arc-window-\($0)" }
    for offset in 0..<count {
        let shuffled = GridGeometry.rotatedIDs(ids, startingAt: offset)
        expect(shuffled.first == ids[offset] && Set(shuffled) == Set(ids) && shuffled.count == count, "shuffle selects the next window and retains every distinct Arc window")
        expect(GridGeometry.rotatedIDs(shuffled, startingAt: count - offset) == ids, "queue rotation is reversible")
    }
}
expect(GridGeometry.rotatedIDs([], startingAt: 1).isEmpty, "empty category shuffle is safe")
var tap = DoubleCommandTap()
expect(!tap.flags(keyCode: 54, commandDown: true, otherModifiers: false, time: 1), "first Command press does not trigger")
expect(!tap.flags(keyCode: 54, commandDown: false, otherModifiers: false, time: 1.05), "single Command tap does not trigger")
expect(!tap.flags(keyCode: 54, commandDown: true, otherModifiers: false, time: 1.15), "second press waits for release")
expect(tap.flags(keyCode: 54, commandDown: false, otherModifiers: false, time: 1.20), "two quick clean Right Command taps trigger organize")
expect(!tap.flags(keyCode: 54, commandDown: false, otherModifiers: false, time: 1.21), "duplicate release never triggers twice")
for kind in 0...4 {
    tap.cancel()
    _ = tap.flags(keyCode: 54, commandDown: true, otherModifiers: false, time: 2)
    _ = tap.flags(keyCode: 54, commandDown: false, otherModifiers: false, time: 2.05)
    switch kind {
    case 0: tap.cancel() // normal Command-key shortcut
    case 1: _ = tap.flags(keyCode: 55, commandDown: true, otherModifiers: false, time: 2.10) // left Command
    case 2: _ = tap.flags(keyCode: 54, commandDown: true, otherModifiers: true, time: 2.10)
    case 3: _ = tap.flags(keyCode: 54, commandDown: true, otherModifiers: false, time: 2.10)
        _ = tap.flags(keyCode: 54, commandDown: false, otherModifiers: false, time: 2.50) // long hold
    default: break // timeout
    }
    let time = kind == 4 ? 3.0 : 2.60
    _ = tap.flags(keyCode: 54, commandDown: true, otherModifiers: false, time: time)
    expect(!tap.flags(keyCode: 54, commandDown: false, otherModifiers: false, time: time + 0.05), "shortcuts, left Command, other modifiers, long holds and slow taps do not trigger")
}
expect(migrated.doubleRightCommand && migrated.snapToGrid && migrated.customRects.isEmpty, "legacy settings gain safe shortcut and editing defaults")

// Shared-border drags work in a packed grid, including T junctions.
for template in Template.allCases {
    var grid = Settings(); grid.template = template
    let rects = Dictionary(uniqueKeysWithValues: grid.enabledLanes.map { ($0.rawValue, ZoneRect(grid.unitRect(for: $0))) })
    for lane in grid.enabledLanes {
        for edge in ResizeEdge.allCases {
            for delta in [-2.0, -0.11, 0.11, 2] {
                let changed = GridGeometry.resizing(rects, lane: lane, edge: edge, dx: delta, dy: delta, snap: false)
                expect(GridGeometry.valid(changed, lanes: grid.enabledLanes), "shared border resize remains bounded and nonoverlapping for every template, edge and extreme drag")
                let r = rects[lane.rawValue]!.cgRect
                let boundary = edge == .left ? r.minX : edge == .right ? r.maxX : edge == .top ? r.minY : r.maxY
                if edge != .bottomRight && boundary > 0.00001 && boundary < 0.99999 {
                    let area = changed.values.reduce(0.0) { $0 + $1.width * $1.height }
                    expect(abs(area - 1) < 0.000001, "dragging an internal divider preserves full display coverage")
                }
            }
        }
    }
}
let packed = Settings()
let packedRects = Dictionary(uniqueKeysWithValues: packed.enabledLanes.map { ($0.rawValue, ZoneRect(packed.unitRect(for: $0))) })
let widenedTerminal = GridGeometry.resizing(packedRects, lane: .terminal, edge: .right, dx: 0.1, dy: 0, snap: false)
expect(abs(widenedTerminal["terminal"]!.width - 0.33) < 0.000001, "terminal can widen without first shrinking a neighbor")
expect(abs(widenedTerminal["simulator"]!.x - 0.33) < 0.000001 && abs(widenedTerminal["simulator"]!.width - 0.09) < 0.000001, "neighbor shrinks to make space while its far edge stays fixed")
let junction = GridGeometry.resizing(packedRects, lane: .preview, edge: .left, dx: 0.05, dy: 0, snap: false)
expect(abs(junction["preview"]!.x - 0.47) < 0.000001 && abs(junction["desktop"]!.x - 0.47) < 0.000001 && abs(junction["simulator"]!.width - 0.24) < 0.000001, "T-junction divider adjusts both stacked regions and their full-height neighbor")
expect(junction["messaging"] == packedRects["messaging"] && junction["media"] == packedRects["media"], "unrelated categories remain fixed during shared resizing")
let reverse = GridGeometry.resizing(widenedTerminal, lane: .terminal, edge: .right, dx: -0.1, dy: 0, snap: false)
for lane in packed.enabledLanes {
    expect(abs(reverse[lane.rawValue]!.x - packedRects[lane.rawValue]!.x) < 0.000001 && abs(reverse[lane.rawValue]!.width - packedRects[lane.rawValue]!.width) < 0.000001, "dragging a border back restores the original layout")
}
var four = Settings(); four.hiddenLanes = ["media", "messaging"]; four.showMediaShelf = false
let fourRects = Dictionary(uniqueKeysWithValues: four.enabledLanes.map { ($0.rawValue, ZoneRect(four.unitRect(for: $0))) })
for lane in four.enabledLanes {
    for edge in ResizeEdge.allCases {
        let resized = GridGeometry.resizing(fourRects, lane: lane, edge: edge, dx: 0.12, dy: 0.12, snap: true)
        expect(GridGeometry.valid(resized, lanes: four.enabledLanes), "the user's four-category configuration supports snapped edge resizing")
    }
}

let customCategory = CustomCategory(name: "Research")
expect(customCategory.lane.isCustom, "named categories have stable custom IDs")
let encodedLane = try JSONEncoder().encode(customCategory.lane)
let decodedCustomLane = try JSONDecoder().decode(Lane.self, from: encodedLane)
expect(decodedCustomLane == customCategory.lane, "custom IDs survive serialization")
let encodedMessaging = try JSONEncoder().encode(Lane.messaging)
expect(String(data: encodedMessaging, encoding: .utf8) == "\"messaging\"", "built-in IDs keep legacy string serialization")
var named = Settings(); named.customCategories = [customCategory]; named.categoryNames[customCategory.id] = "Reading"
named.appRules["com.test.browser"] = customCategory.id
let namedRoundtrip = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(named))
expect(namedRoundtrip.name(customCategory.lane) == "Reading", "renaming preserves category ID")
expect(namedRoundtrip.enabledLanes.contains(customCategory.lane), "named categories are visible after relaunch")
expect(Classifier.lane(bundleID: "com.test.browser", appName: "Browser", title: "", rules: namedRoundtrip.appRules) == customCategory.lane, "persistent app assignments support custom categories")
expect(CategoryDeletionKey.shouldDelete(keyCode: 51, hasModifiers: false, gridSelected: true, isEditingText: false, boardIsKey: true), "Backspace deletes a selected grid section")
expect(CategoryDeletionKey.shouldDelete(keyCode: 117, hasModifiers: false, gridSelected: true, isEditingText: false, boardIsKey: true), "Forward Delete also deletes a selected grid section")
expect(!CategoryDeletionKey.shouldDelete(keyCode: 51, hasModifiers: false, gridSelected: true, isEditingText: true, boardIsKey: true), "typing Backspace into a name or dimension field cannot delete a category")
expect(!CategoryDeletionKey.shouldDelete(keyCode: 51, hasModifiers: true, gridSelected: true, isEditingText: false, boardIsKey: true), "modified Backspace does not delete categories")
expect(!CategoryDeletionKey.shouldDelete(keyCode: 51, hasModifiers: false, gridSelected: true, isEditingText: false, boardIsKey: false), "Backspace in another app cannot delete a grid section")
expect(!CategoryDeletionKey.shouldDelete(keyCode: 51, hasModifiers: false, gridSelected: false, isEditingText: false, boardIsKey: true), "Backspace outside a grid selection is left alone")
expect(!CategoryDeletionKey.shouldDelete(keyCode: 36, hasModifiers: false, gridSelected: true, isEditingText: false, boardIsKey: true), "other keys do not delete categories")
for total in 0...40 {
    for active in 0..<max(1, total) {
        let range = Layout.pickerIndices(total: total, active: active, limit: 16)
        expect(range.count == min(16, total) && range.lowerBound >= 0 && range.upperBound <= total, "window tab strip stays in bounds")
        expect(total == 0 || range.contains(active), "active window always appears among the tabs")
    }
}
var scroll = LaneScrollAccumulator()
for i in 0..<2 { expect(scroll.consume(delta: -2, precise: true, time: Double(i) * 0.01) == nil, "a brush of the trackpad does not switch") }
expect(scroll.consume(delta: -2, precise: true, time: 0.02) == 1, "trackpad scroll switches after a few points")
expect(scroll.consume(delta: -100, precise: true, time: 0.03, momentum: true) == nil, "momentum waits its turn instead of piling onto the finger's step")
expect(scroll.consume(delta: 1, precise: false, time: 0.30) == -1, "mouse wheel scroll selects previous window")
expect(scroll.consume(delta: -1, precise: false, time: 0.50) == 1, "mouse wheel scroll selects next window")
let displays = [CGRect(x: 0, y: 25, width: 5120, height: 1390), CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGRect(x: 20, y: 100, width: 1440, height: 900)]
for display in displays {
    for count in 1...12 {
        let categories = Array(Lane.legacyCases.prefix(min(6, count))) + (0..<max(0, count - 6)).map { _ in CustomCategory(name: "Project").lane }
        let input = categories.enumerated().map { AutoSortItem(lane: $0.element, count: ($0.offset % 4) + 1) }
        let plan = AutoSorter.plan(items: input, screen: display, gap: 12)
        expect(GridGeometry.valid(plan.rects, lanes: categories), "Auto-sort fits every populated category without overlap on ultrawide and ordinary displays")
        expect(abs(plan.rects.values.reduce(0.0) { $0 + $1.width * $1.height } - 1) < 0.000001, "Auto-sort uses the display without leaving gaps")
        expect(plan.capacities.values.allSatisfy { $0 == 1 || $0 == 2 }, "Auto-sort limits simultaneous windows to readable cluster sizes")
        for item in input where item.lane == .messaging || item.lane == .preview { expect(plan.capacities[item.lane.rawValue] == 1, "messaging and browser previews remain individual switchable windows") }
    }
}
let emptySort = AutoSorter.plan(items: [AutoSortItem(lane: .terminal, count: 0)], screen: displays[0], gap: 12)
expect(emptySort.rects.isEmpty, "empty categories consume no Auto-sort space")
let clutter = AutoSorter.plan(items: [.init(lane: .terminal, count: 4), .init(lane: .preview, count: 6), .init(lane: .desktop, count: 4), .init(lane: .messaging, count: 4)], screen: displays[0], gap: 12)
for lane in [Lane.terminal, .preview, .desktop, .messaging] {
    let frame = Layout.frame(unit: clutter.rects[lane.rawValue]!.cgRect, in: displays[0], gap: 12).insetBy(dx: 0, dy: 30)
    let tiles = Layout.tiles(in: frame, count: clutter.capacities[lane.rawValue]!, gap: 12, lane: lane)
    let minimum = AutoSorter.minimumSize(lane)
    expect(tiles.allSatisfy { $0.width >= minimum.width && $0.height >= minimum.height }, "the current clutter workload produces readable tiles on the ultrawide")
}
let measuredItems: [AutoSortItem] = [.init(lane: .terminal, count: 4), .init(lane: .preview, count: 3), .init(lane: .desktop, count: 2), .init(lane: .messaging, count: 4), .init(lane: .media, count: 1, requiredSize: CGSize(width: 620, height: 500))]
let measuredPlan = AutoSorter.plan(items: measuredItems, screen: displays[0], gap: 12)
let measuredPlayer = Layout.frame(unit: measuredPlan.rects["media"]!.cgRect, in: displays[0], gap: 12).insetBy(dx: 0, dy: 30)
expect(measuredPlayer.width >= 620 && measuredPlayer.height >= 500, "Auto-sort reallocates enough room when a player enforces a larger measured minimum")
expect(GridGeometry.valid(measuredPlan.rects, lanes: measuredItems.map(\.lane)), "minimum-size correction preserves a nonoverlapping grid")
print("PASS: \(checks) checks — templates, tiling, multi-display geometry, paging, per-window cycling, keyboard adjustments, classification, custom grid editing, shuffle queues, double-tap detection, and settings.")

// Browsers are separate from media previews, even when their title mentions chat.
for (bundle, app) in [("com.google.Chrome", "Chrome"), ("com.apple.Safari", "Safari"), ("org.mozilla.firefox", "Firefox"), ("com.microsoft.edgemac", "Microsoft Edge"), ("com.brave.Browser", "Brave"), ("company.thebrowser.Browser", "Arc")] {
    expect(Classifier.lane(bundleID: bundle, appName: app, title: "Discord · YouTube · localhost", rules: [:]) == .browser, "browser identity must not be guessed from its current tab title")
}
expect(Classifier.lane(bundleID: "company.thebrowser.Browser", appName: "Arc", title: "News", rules: ["company.thebrowser.Browser": "preview"]) == .preview, "explicit user assignments still override automatic categories")
expect(Lane(rawValue: "browser") == .browser && Lane.allCases.last == .browser, "Browser keeps the six existing shortcut numbers stable")
var browserGrid = Settings(); browserGrid.hiddenLanes = []
expect(GridGeometry.valid(browserGrid.availableLanes.reduce(into: [:]) { $0[$1.rawValue] = ZoneRect(browserGrid.unitRect(for: $1)) }, lanes: browserGrid.enabledLanes), "all seven built-in categories have usable nonoverlapping regions")
let oldGridJSON = "{\"capacities\":{\"terminal\":2},\"customRects\":{},\"hiddenLanes\":[]}"
let oldGrid = try JSONDecoder().decode(Settings.self, from: Data(oldGridJSON.utf8))
expect(oldGrid.hiddenLanes.contains("browser") && !oldGrid.shelvedLanes.contains("browser"), "old layouts preserve geometry until auto-sort discovers the new Browser category")
for preferred in ["arc-work", "arc-other"] {
    let queue = Layout.organizingIDs(["arc-other", "arc-work", "chrome"], preferredID: preferred)
    expect(queue.first == preferred && Set(queue) == Set(["arc-other", "arc-work", "chrome"]), "organize must keep the exact chosen browser window visible without losing other windows")
}
expect(Layout.organizingIDs(["a", "b"], preferredID: "closed") == ["a", "b"], "closed selections leave the remaining queue intact")
let browserWorkload: [AutoSortItem] = [.init(lane: .terminal, count: 8), .init(lane: .browser, count: 13, isFocused: true), .init(lane: .desktop, count: 4), .init(lane: .messaging, count: 4)]
let browserPlan = AutoSorter.plan(items: browserWorkload, screen: displays[0], gap: 12)
expect(GridGeometry.valid(browserPlan.rects, lanes: browserWorkload.map(\.lane)), "a cluttered desktop with Browser gets complete nonoverlapping zones")
expect(browserPlan.capacities["browser"] == 1, "active browser has one foreground window with the rest stacked behind")
expect(browserPlan.rects["browser"]!.width * browserPlan.rects["browser"]!.height > browserPlan.rects["messaging"]!.width * browserPlan.rects["messaging"]!.height, "active Browser receives more space than messaging")
print("PASS: Browser category, legacy migration, exact working-window retention and work-first auto-sort; \(checks) total model checks")

for total in [1, 4, 13] {
    let ids = (0..<total).map { "window-\($0)" }
    for capacity in 1...4 {
        for page in 0..<Layout.pageCount(total: total, capacity: capacity) {
            let stack = Layout.stack(ids: ids, page: page, capacity: capacity, in: CGRect(x: 100, y: 60, width: 1500, height: 900), gap: 12, lane: .browser)
            expect(Set(stack.frames.keys) == Set(ids), "every open window must get a position inside its category")
            expect(Set(stack.raiseOrder) == Set(ids) && stack.raiseOrder.count == ids.count, "stacking must retain every open window exactly once")
            expect(Array(stack.raiseOrder.suffix(stack.foregroundIDs.count)) == stack.foregroundIDs, "chosen windows must be raised last, ahead of queued windows")
            expect(stack.frames.values.allSatisfy { CGRect(x: 100, y: 60, width: 1500, height: 900).contains($0) }, "queued windows must share their category region instead of leaving the desktop")
        }
    }
}
print("PASS: all windows retained in desktop stacks, selected windows raised last; \(checks) total model checks")

// Sifting must touch only the selected foreground windows, never the whole queue.
let switchingIDs = (0..<8).map { "arc-\($0)" }
for index in 0..<switchingIDs.count {
    let direct = Layout.stack(ids: switchingIDs, page: index, capacity: 1, in: CGRect(x: 100, y: 36, width: 1200, height: 850), gap: 12, lane: .browser, presentationOnly: true)
    expect(direct.raiseOrder == [switchingIDs[index]], "switching eight Arc windows must raise only the chosen window")
    expect(Set(direct.frames.keys) == Set([switchingIDs[index]]), "switching must not resize or disturb background windows")
}
let paired = Layout.stack(ids: switchingIDs, page: 2, capacity: 2, in: CGRect(x: 0, y: 36, width: 1800, height: 900), gap: 12, lane: .terminal, presentationOnly: true)
expect(Set(paired.frames.keys) == Set(["arc-4", "arc-5"]) && paired.raiseOrder.count == 2, "multiple visible tiles only touch the new foreground group")
for style in WindowStripStyle.allCases {
    for count in [0, 1, 6, 16, 40] {
        for scale in [0.8, 1.0, 1.5] {
            let metrics = WindowStripMetrics.measure(style: style, count: count, scale: scale, availableWidth: 200)
            expect(metrics.width > 0 && metrics.width <= 200 && metrics.height >= 20 && metrics.reservedHeight == metrics.height + 8, "strip geometry fits the category and reserves only its own height")
        }
    }
}
let referenceDots = WindowStripMetrics.measure(style: .compact, count: 6, scale: 1, availableWidth: 1400)
expect(referenceDots.width < 240 && referenceDots.height == 32, "six-window compact strip stays small")
var stripPrefs = Settings(); stripPrefs.windowStripStyle = .compact; stripPrefs.windowStripScale = 1.3; stripPrefs.categoryStripStyles["browser"] = "detailed"; stripPrefs.useCustomGrid = true
let restoredStripPrefs = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(stripPrefs))
expect(restoredStripPrefs.stripStyle(.browser) == .detailed && restoredStripPrefs.stripStyle(.messaging) == .compact && restoredStripPrefs.windowStripScale == 1.3, "strip style, per-category overrides and size survive launch")
expect(restoredStripPrefs.useCustomGrid, "manual grid policy survives launch")
var oldCustomPayload = try JSONSerialization.jsonObject(with: savedCustom) as! [String: Any]
oldCustomPayload.removeValue(forKey: "useCustomGrid")
let migratedCustom = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: oldCustomPayload))
expect(migratedCustom.useCustomGrid, "saved custom layouts must default to retaining the user's sizes on migration")
print("PASS: direct switching, compact strip geometry, per-category styling and custom-grid policy; \(checks) total model checks")

let originalSlots = ["top-server", "bottom-build"]
let terminalQueue = ["top-server", "bottom-build", "other-project", "logs"]
let topChanged = WindowSlots.replacing(originalSlots, with: "other-project", at: 0)
expect(topChanged == ["other-project", "bottom-build"], "switching the top terminal must leave the bottom terminal unchanged")
let bottomChanged = WindowSlots.replacing(topChanged, with: "logs", at: 1)
expect(bottomChanged == ["other-project", "logs"], "switching the bottom must leave the top terminal unchanged")
expect(WindowSlots.replacing(originalSlots, with: "bottom-build", at: 0) == originalSlots, "clicking an already visible window focuses it instead of replacing or duplicating its peer")
expect(WindowSlots.swapped(originalSlots, 0, 1) == ["bottom-build", "top-server"], "swapping panes exchanges exactly the two visible windows")
expect(WindowSlots.swapped(originalSlots, 1, 1) == originalSlots && WindowSlots.swapped(originalSlots, 0, 5) == originalSlots, "a swap with itself or a missing pane changes nothing")
expect(WindowSlots.nextID(ids: terminalQueue, slots: originalSlots, slot: 0, delta: 1) == "other-project", "sifting top skips the window pinned in the bottom slot")
expect(WindowSlots.nextID(ids: terminalQueue, slots: originalSlots, slot: 1, delta: -1) == "logs", "reverse cycling bottom skips the pinned top window")
let independentPlan = Layout.stack(ids: terminalQueue, foreground: topChanged, in: CGRect(x: 0, y: 36, width: 900, height: 1200), gap: 12, lane: .terminal, presentationOnly: true, onlyIDs: ["other-project"])
expect(independentPlan.raiseOrder == ["other-project"] && independentPlan.frames.count == 1, "independent terminal switching must resize and raise only the replacement window")
expect(WindowSlots.normalized(["closed", "top-server", "top-server"], ids: terminalQueue, capacity: 2) == ["bottom-build", "top-server"], "closed or duplicate slots recover without moving a valid peer to another slot")
expect(WindowSlots.reordered(terminalQueue, source: "logs", before: "top-server") == ["logs", "top-server", "bottom-build", "other-project"], "dragging the last tab ahead of the first preserves every window and the relative order of the others")
expect(WindowSlots.reordered(terminalQueue, source: "invalid", before: "top-server") == terminalQueue, "unrelated tab drops cannot corrupt ordering")
var namedWindows = Settings(); namedWindows.windowLabels = ["top-server": "Server", "bottom-build": "Build"]; namedWindows.windowOrder["terminal"] = terminalQueue
let restoredNames = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(namedWindows))
expect(restoredNames.windowLabels == namedWindows.windowLabels && restoredNames.windowOrder == namedWindows.windowOrder, "window names and queue order persist while the same windows remain open")
print("PASS: independent terminal slots, no peer flashing, tab ordering and labels; \(checks) total model checks")

expect(WindowSlots.normalized(["closed-top", "bottom-build"], ids: terminalQueue, capacity: 2) == originalSlots, "closing the top terminal keeps the bottom terminal in its slot")
let oldPeerFrame = Layout.tiles(in: CGRect(x: 0, y: 36, width: 900, height: 1200), count: 2, gap: 12, lane: .terminal)[1]
let incremental = Layout.stack(ids: terminalQueue, foreground: originalSlots, in: CGRect(x: 0, y: 36, width: 900, height: 1200), gap: 12, lane: .terminal, onlyIDs: ["other-project"], slotCount: 2)
expect(Set(incremental.frames.keys) == Set(["other-project"]) && !incremental.frames.keys.contains("bottom-build"), "placing a new terminal must not issue move or raise operations for existing terminals")
let singleSlot = Layout.stack(ids: ["top-server"], foreground: ["top-server"], in: CGRect(x: 0, y: 36, width: 900, height: 1200), gap: 12, lane: .terminal, slotCount: 2)
expect(singleSlot.frames["top-server"]!.maxY < oldPeerFrame.minY, "configured slots retain their geometry before a second terminal opens")
print("PASS: incremental window placement and stable slot geometry; \(checks) total model checks")

expect(WindowSlots.normalized(["closed-top", "bottom-build"], ids: ["bottom-build"], capacity: 2) == ["", "bottom-build"], "a vacant top slot must not pull the remaining bottom terminal out of place")
let vacantTop = Layout.stack(ids: ["bottom-build"], foreground: ["", "bottom-build"], in: CGRect(x: 0, y: 36, width: 900, height: 1200), gap: 12, lane: .terminal, slotCount: 2)
expect(vacantTop.frames["bottom-build"] == oldPeerFrame, "bottom geometry stays fixed when the top window closes")
print("PASS: vacant slots preserve peers; \(checks) total model checks")

expect(WindowSlots.reordered(terminalQueue, source: "top-server", before: "logs", after: true) == ["bottom-build", "other-project", "logs", "top-server"], "dropping on the right half of the last tab can move a tab to the end")
print("PASS: before/after tab drops; \(checks) total model checks")

let migratedDots = try JSONDecoder().decode(Settings.self, from: Data(#"{"windowStripStyle":"dots","categoryStripStyles":{"browser":"dots"}}"#.utf8))
expect(migratedDots.windowStripStyle == .compact && migratedDots.stripStyle(.browser) == .compact, "old Dots choices migrate to Compact")
expect(WindowStripStyle.allCases == [.compact, .detailed, .expanding], "Compact, Detailed and Expand on hover are offered")
for (key, action) in StripKeyAction.bindings {
    expect(StripKeyAction.action(keyCode: key, hasModifiers: false, hovering: true) == action, "hovered bare arrows and number keys select the matching action")
    expect(StripKeyAction.action(keyCode: key, hasModifiers: false, hovering: false) == nil, "keyboard behavior outside a strip stays normal")
    expect(StripKeyAction.action(keyCode: key, hasModifiers: true, hovering: true) == nil, "modified app shortcuts stay normal even over a strip")
}
expect(StripKeyAction.action(keyCode: 0, hasModifiers: false, hovering: true) == nil, "typing letters is never intercepted")
let pairedBrowsers = Layout.tiles(in: CGRect(x: 0, y: 0, width: 900, height: 1000), count: 2, gap: 12, lane: .browser)
expect(pairedBrowsers[0].minY == pairedBrowsers[1].minY && pairedBrowsers[0].maxX < pairedBrowsers[1].minX, "two Browser windows sit side by side even in a tall region")
print("PASS: hovered bare keys, style migration and browser side-by-side; \(checks) total model checks")

let olderStrips = try JSONDecoder().decode(Settings.self, from: Data(#"{"showLaneControls":true}"#.utf8))
expect(olderStrips.stripPlacement == .onWindows && !olderStrips.stripReservesSpace, "older settings put strips on the windows with no padding")
var reserving = Settings(); reserving.stripPlacement = .aboveWindows
expect(reserving.stripReservesSpace, "Above the windows keeps the reserved band")
reserving.showLaneControls = false
expect(!reserving.stripReservesSpace, "hidden strips never reserve space")
var placedStrips = Settings(); placedStrips.stripPlacement = .aboveWindows
placedStrips.stripPositions = ["terminal": StripPosition(x: 0.25, y: 0.5)]
let placedRoundtrip = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(placedStrips))
expect(placedRoundtrip.stripPlacement == .aboveWindows, "strip placement survives a restart")
expect(placedRoundtrip.stripPositions == ["terminal": StripPosition(x: 0.25, y: 0.5)], "moved strip positions survive a restart")
let brokenStrips = try JSONDecoder().decode(Settings.self, from: Data(#"{"gap":20,"stripPositions":{"terminal":"oops"}}"#.utf8))
expect(brokenStrips.gap == 20 && brokenStrips.stripPositions.isEmpty, "a damaged strip position never resets the rest of the settings")
let stripRegion = CGRect(x: 12, y: 82, width: 1500, height: 1346), stripScreen = CGRect(x: 0, y: 38, width: 5120, height: 1402)
let stripSize = CGSize(width: 220, height: 32)
let centeredStrip = StripPlacementGeometry.frame(size: stripSize, region: stripRegion, bounds: stripScreen, saved: nil)
expect(abs(centeredStrip.midX - stripRegion.midX) < 0.001 && centeredStrip.minY == stripRegion.minY, "default strip is centered on the region's top edge")
for spot in [CGPoint(x: 900, y: 600), CGPoint(x: 130, y: 1300), CGPoint(x: 1450, y: 120), CGPoint(x: 2600, y: 700)] {
    let dragged = CGRect(x: spot.x - 110, y: spot.y - 16, width: 220, height: 32)
    let saved = StripPlacementGeometry.position(of: dragged, in: stripRegion)
    let restored = StripPlacementGeometry.frame(size: stripSize, region: stripRegion, bounds: stripScreen, saved: saved)
    expect(abs(restored.minX - dragged.minX) < 0.001 && abs(restored.minY - dragged.minY) < 0.001, "a dragged strip comes back exactly where it was dropped")
}
let wideRegion = CGRect(x: 12, y: 82, width: 3000, height: 1346)
let movedStrip = StripPlacementGeometry.frame(size: stripSize, region: wideRegion, bounds: stripScreen, saved: StripPosition(x: 0.75, y: 0.5))
expect(abs(movedStrip.midX - (12 + 2250)) < 0.001, "a moved strip follows its region when the region is resized")
for wild in [StripPosition(x: -3, y: -3), StripPosition(x: 9, y: 9)] {
    let clamped = StripPlacementGeometry.frame(size: stripSize, region: stripRegion, bounds: stripScreen, saved: wild)
    expect(stripScreen.contains(clamped), "a strip dragged off the display stays fully on screen")
}
print("PASS: strip placement and dragging; \(checks) total model checks")

let tile = CGRect(x: 12, y: 82, width: 787, height: 318)
let shownTab = SeenWindow(id: "1627-old-tab", pid: 1627, frame: tile)
let newTab = SeenWindow(id: "1627-new-tab", pid: 1627, frame: tile)
expect(TabSwitch.pairs(vanished: [shownTab], appeared: [newTab]) == ["1627-new-tab": "1627-old-tab"], "switching a Ghostty tab hands the new tab the old tab's slot")
expect(TabSwitch.pairs(vanished: [shownTab], appeared: [SeenWindow(id: "6579-x", pid: 6579, frame: tile)]).isEmpty, "a different app's window in the same spot is not a tab switch")
expect(TabSwitch.pairs(vanished: [shownTab], appeared: [SeenWindow(id: "1627-moved", pid: 1627, frame: tile.offsetBy(dx: 300, dy: 0))]).isEmpty, "a new window elsewhere is a new window, not a tab")
expect(TabSwitch.pairs(vanished: [], appeared: [newTab]).isEmpty, "opening a window without closing one is never a tab switch")
let twoSwaps = TabSwitch.pairs(vanished: [shownTab, SeenWindow(id: "1627-b", pid: 1627, frame: tile.offsetBy(dx: 0, dy: 330))],
                               appeared: [SeenWindow(id: "1627-b2", pid: 1627, frame: tile.offsetBy(dx: 0, dy: 330)), newTab])
expect(twoSwaps == ["1627-b2": "1627-b", "1627-new-tab": "1627-old-tab"], "two tab groups switching at once each keep their own tile")
expect(TabSwitch.pairs(vanished: [shownTab], appeared: [SeenWindow(id: "1627-snap", pid: 1627, frame: CGRect(x: 11, y: 84, width: 787, height: 318))]).count == 1, "a tab window a pixel off still counts as the same spot")

// Three terminals of one app stacked in one tile, a browser beside them.
let top = CGRect(x: 12, y: 82, width: 787, height: 318), bottom = CGRect(x: 12, y: 411, width: 787, height: 318)
let appOrder = [SeenWindow(id: "t-front", pid: 1627, frame: top), SeenWindow(id: "t-low", pid: 1627, frame: bottom),
                SeenWindow(id: "t-middle", pid: 1627, frame: top), SeenWindow(id: "t-back", pid: 1627, frame: top),
                SeenWindow(id: "arc", pid: 1629, frame: CGRect(x: 810, y: 82, width: 2862, height: 1346))]
let serverStack: [(pid: Int32, frame: CGRect)] = [(1629, CGRect(x: 810, y: 82, width: 2862, height: 1346)), (1627, top), (1627, bottom), (1627, top), (1627, top)]
let stackPositions = StackOrder.positions(windows: appOrder, onScreen: serverStack)
expect(stackPositions == ["arc": 0, "t-front": 1, "t-low": 2, "t-middle": 3, "t-back": 4], "stacked windows of one app keep their front-to-back order")
let restart = StackOrder.adoptedSlots(tiles: [top, bottom], windows: appOrder.filter { $0.pid == 1627 }.reversed(), order: stackPositions)
expect(restart.slots == ["t-front", "t-low"], "after a restart each tile shows the window that is really in front")
expect(Set(restart.adopted) == ["t-front", "t-low", "t-middle", "t-back"], "every window already in its tiles is picked up without moving")
let stray = StackOrder.adoptedSlots(tiles: [top], windows: [SeenWindow(id: "elsewhere", pid: 1, frame: CGRect(x: 2000, y: 500, width: 600, height: 400))], order: ["elsewhere": 0])
expect(stray.adopted.isEmpty && stray.slots == [""], "windows outside their category are left for placement")
let hiddenBehind = StackOrder.adoptedSlots(tiles: [top], windows: [SeenWindow(id: "off-screen", pid: 1627, frame: top)], order: [:])
expect(hiddenBehind.adopted == ["off-screen"] && hiddenBehind.slots == [""], "a window not on screen is adopted but never claims the visible slot")
let clamped = StackOrder.adoptedSlots(tiles: [top], windows: [SeenWindow(id: "snapped", pid: 1627, frame: CGRect(x: 12, y: 84, width: 780, height: 310))], order: ["snapped": 0])
expect(clamped.slots == ["snapped"], "an app that snaps its size slightly still counts as inside its tile")
print("PASS: tab switches and picking up the layout after a restart; \(checks) total model checks")

let ultrawide = CGRect(x: 0, y: 38, width: 5120, height: 1402)
let centered = NewWindowCenter.frame(for: CGSize(width: 1494, height: 876), in: ultrawide, gap: 12)
expect(abs(centered.midX - ultrawide.midX) <= 1 && abs(centered.midY - ultrawide.midY) <= 1 && centered.width == 1494 && centered.height == 876, "a new window opens centered at its own size")
let oversized = NewWindowCenter.frame(for: CGSize(width: 6000, height: 2000), in: ultrawide, gap: 12)
expect(ultrawide.contains(oversized) && oversized.width == 5096 && oversized.height == 1378, "a window bigger than the display is shrunk to fit inside the gaps")
let quietDefault = try JSONDecoder().decode(Settings.self, from: Data(#"{"autoArrange":false}"#.utf8))
expect(quietDefault.newWindowPlacement == .center, "with automatic placement off, new windows open centered")
let placingDefault = try JSONDecoder().decode(Settings.self, from: Data(#"{"autoArrange":true}"#.utf8))
expect(placingDefault.newWindowPlacement == .category, "people who chose automatic placement keep it")
var choice = Settings()
for option in NewWindowPlacement.allCases {
    choice.newWindowPlacement = option
    let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(choice))
    expect(back.newWindowPlacement == option, "the \(option.title) choice survives a restart")
}
choice.newWindowPlacement = .leave
expect(!choice.autoArrange && !choice.centerNewWindows, "Leave turns off both placement and centering")
print("PASS: new windows open centered; \(checks) total model checks")

var swipe = LaneScrollAccumulator(), swipeSteps = 0
for i in 0..<20 { if swipe.consume(delta: -4, precise: true, time: 10 + Double(i) * 0.016) == 1 { swipeSteps += 1 } }
expect(swipeSteps >= 5, "one ordinary trackpad swipe moves through several windows")
var wheel = LaneScrollAccumulator(), wheelSteps = 0
for i in 0..<10 { if wheel.consume(delta: -1, precise: false, time: 20 + Double(i) * 0.06) == 1 { wheelSteps += 1 } }
expect(wheelSteps == 10, "every wheel notch switches when spun at normal speed")
let gridRegions = [CGRect(x: 12, y: 42, width: 787, height: 1386), CGRect(x: 810, y: 42, width: 2862, height: 1386)]
expect(StrayWindow.coversGrid(CGRect(x: 12, y: 42, width: 787, height: 600), regions: gridRegions), "a window left on a category tile is cleared by Organize")
expect(!StrayWindow.coversGrid(CGRect(x: 3700, y: 400, width: 600, height: 400), regions: gridRegions), "a window beside the grid is left alone")
expect(!StrayWindow.coversGrid(CGRect(x: 700, y: 400, width: 120, height: 400).offsetBy(dx: 3000, dy: 0), regions: gridRegions), "a window barely touching a region is left alone")
print("PASS: faster strip scrolling and windows outside the grid; \(checks) total model checks")

expect(!WindowStripMetrics.needsStrip(windowCount: 0) && !WindowStripMetrics.needsStrip(windowCount: 1), "a category with one window or none shows no strip")
expect(WindowStripMetrics.needsStrip(windowCount: 2), "a second window brings the strip back")
print("PASS: single-window categories have no strip; \(checks) total model checks")

let idle = WindowStripMetrics.measure(style: .expanding, count: 6, scale: 1, availableWidth: 1500, slots: 2)
let compactSize = WindowStripMetrics.measure(style: .compact, count: 6, scale: 1, availableWidth: 1500, slots: 2)
let detailedSize = WindowStripMetrics.measure(style: .detailed, count: 6, scale: 1, availableWidth: 1500, slots: 2)
expect(idle.width == compactSize.width && idle.height == compactSize.height && idle.reservedHeight == compactSize.reservedHeight, "Expand on hover rests at the compact size and reserves only that")
expect(detailedSize.width >= idle.width && detailedSize.height >= idle.height, "the expanded strip covers the resting strip, so the mouse stays inside")
let expandRegion = CGRect(x: 12, y: 82, width: 1500, height: 1346)
for saved in [nil, StripPosition(x: 0.4, y: 0.3)] as [StripPosition?] {
    let rest = StripPlacementGeometry.frame(size: CGSize(width: idle.width, height: idle.height), region: expandRegion, bounds: stripScreen, saved: saved)
    let grown = StripPlacementGeometry.frame(size: CGSize(width: detailedSize.width, height: detailedSize.height), region: expandRegion, bounds: stripScreen, saved: saved)
    let expandedFrame = StripPlacementGeometry.grown(rest: rest, size: CGSize(width: grown.width, height: grown.height), bounds: stripScreen)
    expect(expandedFrame.contains(rest), "the expanded strip covers the resting strip, so the mouse stays inside")
    expect(expandedFrame.minX == rest.minX && expandedFrame.minY == rest.minY, "the strip grows to the right: the name and Top/Bottom never move")
}
var hoverStyle = Settings(); hoverStyle.windowStripStyle = .expanding
let hoverRoundtrip = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(hoverStyle))
expect(hoverRoundtrip.windowStripStyle == .expanding, "Expand on hover survives a restart")
print("PASS: Expand on hover strips; \(checks) total model checks")

let twoWide = WindowStripMetrics.measure(style: .detailed, count: 2, scale: 1, availableWidth: 3000)
let sixWide = WindowStripMetrics.measure(style: .detailed, count: 6, scale: 1, availableWidth: 3000)
let manyWide = WindowStripMetrics.measure(style: .detailed, count: 16, scale: 1, availableWidth: 3000)
expect(twoWide.width == WindowStripMetrics.chipRoom(slots: 1) + 2 * WindowStripMetrics.chipWidth, "two windows get a short bar with no empty stretch")
expect(twoWide.width < sixWide.width && sixWide.width <= 760 && manyWide.width == 760, "the bar grows with its windows up to a full-width bar")
for count in 2...16 {
    let bar = WindowStripMetrics.measure(style: .detailed, count: count, scale: 1, availableWidth: 3000)
    let perChip = (bar.width - WindowStripMetrics.chipRoom(slots: 1)) / Double(count)
    expect(perChip <= WindowStripMetrics.chipWidth + 0.001, "chips fill the bar without leaving a gap (\(count) windows)")
    expect(bar.width >= WindowStripMetrics.measure(style: .expanding, count: count, scale: 1, availableWidth: 3000).width, "the expanded bar still covers the resting pill (\(count) windows)")
}
print("PASS: detailed strips fit their windows; \(checks) total model checks")

var flick = LaneScrollAccumulator(), flickSteps = 0, flickTime = 30.0
for _ in 0..<4 { flickTime += 0.012; if flick.consume(delta: -9, precise: true, time: flickTime) == 1 { flickSteps += 1 } }
let fingerSteps = flickSteps
var momentumDelta = 40.0
while momentumDelta > 1 { flickTime += 0.016; if flick.consume(delta: -momentumDelta, precise: true, time: flickTime, momentum: true) == 1 { flickSteps += 1 }; momentumDelta *= 0.9 }
expect(fingerSteps >= 2, "a quick 50 ms flick switches twice while the finger moves")
expect(flickSteps > fingerSteps && flickSteps - fingerSteps <= 8, "a flick's momentum carries a few more windows, then stops")
let atEdge = StripPlacementGeometry.grown(rest: CGRect(x: 4950, y: 42, width: 150, height: 26), size: CGSize(width: 460, height: 26), bounds: stripScreen)
expect(atEdge.maxX <= stripScreen.maxX - StripPlacementGeometry.edgeMargin, "a strip near the display's right edge grows leftward and stays clear of the edge")
print("PASS: responsive scrolling and strips that grow in place; \(checks) total model checks")

let browserTile = CGRect(x: 810, y: 42, width: 2862, height: 1346), browser2Tile = CGRect(x: 3683, y: 42, width: 549, height: 1346)
let terminalTop = CGRect(x: 12, y: 42, width: 787, height: 318), terminalBottom = CGRect(x: 12, y: 371, width: 787, height: 318)
let browserTwo = CustomCategory(name: "Browser 2").lane
let layoutTiles: [(lane: Lane, tile: CGRect)] = [(.browser, browserTile), (browserTwo, browser2Tile), (.terminal, terminalTop), (.terminal, terminalBottom)]
expect(TileMembership.category(of: browser2Tile, tiles: layoutTiles) == browserTwo, "a new Arc window opened over Browser 2 counts in Browser 2")
expect(TileMembership.category(of: CGRect(x: 3690, y: 48, width: 540, height: 1330), tiles: layoutTiles) == browserTwo, "a window an app sized a few points off still fills its tile")
expect(TileMembership.category(of: terminalBottom, tiles: layoutTiles) == .terminal, "a window in the lower terminal pane counts in Terminal")
expect(TileMembership.category(of: CGRect(x: 1813, y: 263, width: 1494, height: 876), tiles: layoutTiles) == nil, "a centered floating window belongs to no category")
expect(TileMembership.category(of: CGRect(x: 12, y: 371, width: 787, height: 600), tiles: layoutTiles) == nil, "a window hanging half out of a pane is not counted there")
expect(TileMembership.category(of: CGRect(x: 3000, y: 300, width: 1000, height: 600), tiles: layoutTiles) == nil, "a window straddling two categories belongs to neither")
print("PASS: categories follow where windows sit; \(checks) total model checks")

let restingAtEdge = StripPlacementGeometry.frame(size: CGSize(width: 150, height: 26), region: CGRect(x: 4209, y: 42, width: 899, height: 1346), bounds: stripScreen, saved: StripPosition(x: 1.2, y: 0.02))
expect(restingAtEdge.maxX <= stripScreen.maxX - StripPlacementGeometry.edgeMargin && restingAtEdge.minX >= stripScreen.minX, "a resting strip dragged toward the edge also keeps the margin")
let samples: [(String, String, String, String)] = [
    ("✳ Shop site hosting", "Ghostty", "com.mitchellh.ghostty", "Shop site hosting"),
    ("Rate the script | sam", "Ghostty", "com.mitchellh.ghostty", "Rate the script"),
    ("⠼ Build Japanese lockscreen widget | sam", "Ghostty", "com.mitchellh.ghostty", "Build Japanese lockscreen"),
    ("Organization and readability", "Ghostty", "com.mitchellh.ghostty", "Organization and readability"),
    ("Planning the move and", "Ghostty", "com.mitchellh.ghostty", "Planning the move"),
    ("✳ Flashcards lockscreen widget app", "Ghostty", "com.mitchellh.ghostty", "Flashcards lockscreen widget"),
    ("Atlas — Version Showcase", "Arc", "company.thebrowser.Browser", "Atlas · Version Showcase"),
    ("\u{200E}\u{2068}Mika | TradeClubVN\u{2069} – (1265790)", "Arc", "company.thebrowser.Browser", "Mika · TradeClubVN"),
    ("◑ Lanes app feature ideas", "Ghostty", "com.mitchellh.ghostty", "Lanes app feature ideas"),
    ("(2) Instagram • Messages", "Arc", "company.thebrowser.Browser", "Instagram · Messages"),
    ("0.017970 | XYZUSDT | Trade XYZUSDT, Share Your Position Profits & Loss", "Arc", "company.thebrowser.Browser", "XYZUSDT"),
    ("Issues · Mak5er/AirCard · GitHub", "Arc", "company.thebrowser.Browser", "Issues · Mak5er/AirCard"),
    ("CITY APARTMENT HUNTING, Street Food, Night Market", "Arc", "company.thebrowser.Browser", "CITY APARTMENT HUNTING"),
    ("It Seems Like You're Ready", "Arc", "company.thebrowser.Browser", "It Seems Like You're Ready"),
    ("README.md — Lanes", "Xcode", "com.apple.dt.Xcode", "README.md · Lanes"),
    ("WhatsApp", "\u{200E}WhatsApp", "net.whatsapp.WhatsApp", "WhatsApp"),
    ("Arc", "Arc", "company.thebrowser.Browser", "Arc"),
    ("", "Finder", "com.apple.finder", "Finder"),
    ("Ana Lee Sam Kim", "WhatsApp", "net.whatsapp.WhatsApp", "WhatsApp"),
    ("Mika | TradeClubVN", "Telegram", "ru.keepcoder.Telegram", "Telegram"),
    ("Lark", "Lark", "com.larksuite.Lark", "Lark"),
    ("Messages", "Messages", "com.apple.MobileSMS", "Messages"),
]
for (title, app, bundle, want) in samples {
    let got = TitleSummary.label(title: title, appName: app, bundleID: bundle)
    expect(got == want, "short tab name for \"\(title)\" is \"\(want)\" (got \"\(got)\")")
    expect(got.count <= TitleSummary.limit, "short tab names stay short")
}
expect(TitleSummary.shortTitle("Ana Lee Sam Kim", appName: "WhatsApp") == "Ana Lee Sam Kim", "a second chat window can still say which conversation it is")
let shortDefault = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
expect(shortDefault.shortTabNames, "short tab names are on by default")
print("PASS: short tab names and strips clear of the display edge; \(checks) total model checks")

expect(Settings().newWindowPlacement == .leave, "plain defaults leave new windows where their app opens them")
expect(Settings().centerNewWindows == false && Settings().autoArrange == false, "plain defaults move nothing on their own")
print("PASS: release defaults; \(checks) total model checks")

let oldShuffle = try JSONDecoder().decode(Settings.self, from: Data(#"{"gap":20,"doubleTapAction":"shuffle","doubleRightCommand":true}"#.utf8))
expect(oldShuffle.gap == 20 && oldShuffle.doubleRightCommand, "a settings file from when Shuffle existed still loads with everything else kept")
print("PASS: Shuffle removed safely; \(checks) total model checks")

let firstRun = TourGuide.steps(trusted: false), returning = TourGuide.steps(trusted: true)
expect(firstRun.first?.spot == .permission && returning.first?.spot == .organize, "the tour starts with window control only when it is still off")
expect(firstRun.count == returning.count + 1 && returning.last?.spot == .openLanes, "the tour ends on how to open Lanes again")
expect(returning.allSatisfy { !$0.body.contains("⌘") && !$0.body.contains("⌥") && !$0.body.contains("⌃") }, "the tour spells out key names instead of symbols")
expect(returning.last?.body.contains("menu bar") == true && returning.last?.body.contains("Control, Option and Command") == true && returning.last?.body.contains("Dock") == true, "the last step names the menu bar icon, the shortcut and the Dock")
expect(returning.allSatisfy { !$0.title.isEmpty && $0.body.count > 40 }, "every tour step explains itself")
expect(returning.contains { $0.spot == .restore && $0.body.contains("back where it was") }, "the tour explains Restore")
expect(returning.filter { $0.spot == nil }.count == 1, "one step shows the strips on the screen")
expect(!returning.contains { ($0.title + $0.body).lowercased().contains("shuffle") }, "the tour never mentions removed features")
expect(!Settings().hasSeenTour, "a fresh install shows the tour")
var toured = Settings(); toured.hasSeenTour = true
let touredBack = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(toured))
expect(touredBack.hasSeenTour, "the tour is shown once")
print("PASS: first-run tour; \(checks) total model checks")

let presetLanes: [Lane] = [.terminal, .browser, .messaging, .desktop, .preview, CustomCategory(name: "Terminal 2").lane, CustomCategory(name: "Browser 2").lane, .simulator]
for n in 1...presetLanes.count {
    let lanes = Array(presetLanes.prefix(n))
    let counts = Dictionary(uniqueKeysWithValues: lanes.enumerated().map { ($1, [4, 6, 3, 1, 0, 2, 1, 0][$0]) })
    for shape in PresetShape.allCases {
        let main = lanes[min(1, n - 1)]
        let r = shape.rects(lanes: lanes, main: main, windows: counts)
        expect(GridGeometry.valid(r, lanes: lanes), "\(shape.title) fits \(n) categories with no overlap")
        expect(abs(r.values.reduce(0.0) { $0 + $1.width * $1.height } - 1) < 0.0001, "\(shape.title) uses the whole display for \(n) categories")
        if shape != .columns && n > 1 {
            let area = { (l: Lane) in (r[l.rawValue]?.width ?? 0) * (r[l.rawValue]?.height ?? 0) }
            expect(lanes.allSatisfy { $0 == main || area($0) < area(main) }, "\(shape.title) gives the main category the most room")
        }
    }
}
let busy = PresetShape.columns.rects(lanes: [.terminal, .browser], main: .terminal, windows: [.terminal: 0, .browser: 8])
expect((busy["browser"]?.width ?? 0) > 0.5, "Columns gives the busier category the wider column")
expect(PresetShape.focus.rects(lanes: [.browser], main: .browser, windows: [:])["browser"]?.width == 1, "a single category fills the display")
print("PASS: presets fit any categories; \(checks) total model checks")

let first = Settings.firstRun
expect(first.enabledLanes == [.browser] && first.customRects == ["browser": ZoneRect(CGRect(x: 0, y: 0, width: 1, height: 1))], "a new install starts with Browser filling the grid")
expect(Set(first.hiddenLanes + first.shelvedLanes) == Set(Lane.legacyCases.map(\.rawValue)) && first.customCategories.isEmpty, "every other category waits on the shelf, and there are no extra categories")
expect(first.windowStripStyle == .expanding && first.windowStripScale == 0.8 && first.stripPlacement == .onWindows && first.shortTabNames, "strips expand on hover, small, on the windows, with short names")
expect(first.newWindowPlacement == .center && first.useCustomGrid && !first.hasSeenTour, "new windows open centered, Organize keeps the grid, and the tour shows once")
expect(first.windowCategories.isEmpty && first.windowLabels.isEmpty && first.windowOrder.isEmpty && first.savedLayouts.isEmpty && first.stripPositions.isEmpty && first.appRules.isEmpty, "nothing personal ships in the defaults")
let firstBack = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(first))
expect(firstBack.enabledLanes == first.enabledLanes && firstBack.customRects == first.customRects, "the starting setup survives its first save and reload")
var firstLaptop = Settings.firstRun
expect(firstLaptop.switchDisplay(to: "Built-in Retina Display 1512×982", kind: .standard, fresh: true) && firstLaptop.enabledLanes == [.browser] && firstLaptop.customRects["browser"]?.width == 1, "on a MacBook a new install also starts with Browser alone")
print("PASS: recommended setup for new installs; \(checks) total model checks")

expect(DisplayKind.of(CGSize(width: 5120, height: 1440)) == .wide && DisplayKind.of(CGSize(width: 3440, height: 1440)) == .wide, "32:9 and 21:9 displays are wide")
expect(DisplayKind.of(CGSize(width: 1512, height: 982)) == .standard && DisplayKind.of(CGSize(width: 2560, height: 1440)) == .standard, "a MacBook and a 16:9 monitor are standard")
// Your ultrawide grid, then unplug: the MacBook gets its own layout.
var desk = Settings.sampleDesk
expect(!desk.switchDisplay(to: "Odyssey G93SD 5120×1440", kind: .wide), "the first display keeps the grid already in use")
let ultrawideRects = desk.customRects, ultrawideLanes = desk.enabledLanes
expect(desk.switchDisplay(to: "Built-in Retina Display 1512×982", kind: .standard), "unplugging the ultrawide switches to a MacBook grid")
expect(Set(desk.enabledLanes) == [.browser, .terminal, .messaging], "the MacBook grid keeps Browser, Terminal and Messaging")
expect(GridGeometry.valid(desk.customRects, lanes: desk.enabledLanes) && abs((desk.customRects["browser"]?.width ?? 0) - 0.6) < 0.0001, "Browser takes the left 60% with no overlaps")
expect(desk.enabledLanes.allSatisfy { desk.capacity($0) == 1 }, "one window at a time on a laptop")
expect(desk.availableLanes.contains(Settings.browserTwo.lane) && desk.shelvedLanes.contains(Settings.terminalTwo.lane.rawValue), "Browser 2 and Terminal 2 wait on the shelf, not deleted")
desk.capacities["messaging"] = 2
expect(desk.switchDisplay(to: "Odyssey G93SD 5120×1440", kind: .wide), "plugging the ultrawide back in switches again")
expect(desk.customRects == ultrawideRects && desk.enabledLanes == ultrawideLanes && desk.capacity(.terminal) == 2, "the ultrawide grid comes back exactly as it was")
expect(desk.switchDisplay(to: "Built-in Retina Display 1512×982", kind: .standard) && desk.capacity(.messaging) == 2, "changes made on the MacBook are kept for the MacBook")
expect(!desk.switchDisplay(to: "Built-in Retina Display 1512×982", kind: .standard), "the same display never switches")
// A second wide monitor borrows the wide grid; a new install on a laptop starts with the laptop layout.
expect(desk.switchDisplay(to: "Studio Display Wide 3440×1440", kind: .wide) && desk.customRects == ultrawideRects, "a new wide display starts from your wide grid")
var laptopInstall = Settings.sampleDesk
expect(laptopInstall.switchDisplay(to: "Built-in Retina Display 1512×982", kind: .standard, fresh: true) && Set(laptopInstall.enabledLanes) == [.browser, .terminal, .messaging], "a new install on a MacBook starts with the laptop layout")
var existing = Settings.sampleDesk
expect(!existing.switchDisplay(to: "Built-in Retina Display 1512×982", kind: .standard, fresh: false) && existing.customRects == Settings.sampleDesk.customRects, "an existing setup is never replaced just by updating")
let deskBack = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(desk))
expect(deskBack.displayLayouts == desk.displayLayouts && deskBack.activeDisplayKey == desk.activeDisplayKey, "every display's grid survives a restart")
let onlyBrowser = { () -> Settings in var s = Settings(); s.customCategories = []; s.hiddenLanes = Lane.allCases.filter { $0 != .browser }.map(\.rawValue); s.customRects = [:]; return s }()
expect(GridGeometry.valid(onlyBrowser.laptopLayout().customRects, lanes: [.browser]), "a single category fills a laptop screen")
print("PASS: MacBook mode and per-display grids; \(checks) total model checks")

let halves: [String: ZoneRect] = ["terminal": ZoneRect(CGRect(x: 0, y: 0, width: 0.5, height: 1)), "browser": ZoneRect(CGRect(x: 0.5, y: 0, width: 0.5, height: 1))]
let both: [Lane] = [.terminal, .browser]
expect(GridGeometry.snapPlan(.terminal, candidate: CGRect(x: 0.3, y: 0, width: 0.5, height: 1), at: CGPoint(x: 0.7, y: 0.5), rects: halves, lanes: both) == .swap(.browser), "dropping a category on another one swaps them")
expect(GridGeometry.snapPlan(.terminal, candidate: CGRect(x: 0, y: 0, width: 0.4, height: 1), at: CGPoint(x: 0.2, y: 0.5), rects: halves, lanes: both) == .move(CGRect(x: 0, y: 0, width: 0.4, height: 1)), "a move that fits stays exactly where it was dropped")
let gap: [String: ZoneRect] = ["terminal": ZoneRect(CGRect(x: 0, y: 0, width: 0.4, height: 1)), "browser": ZoneRect(CGRect(x: 0.6, y: 0, width: 0.4, height: 1))]
let fitted = GridGeometry.snapPlan(.terminal, candidate: CGRect(x: 0.45, y: 0, width: 0.4, height: 1), at: CGPoint(x: 0.5, y: 0.5), rects: gap, lanes: both)
if case .fit(let r) = fitted {
    expect(GridGeometry.valid(r, lanes: both) && (r["terminal"]?.cgRect.contains(CGPoint(x: 0.5, y: 0.5)) ?? false), "dropping on free space fills that space without overlaps")
} else { expect(false, "dropping on free space fills that space without overlaps") }
let swapped = GridGeometry.snapPlan(.browser, candidate: CGRect(x: -0.2, y: 0, width: 0.5, height: 1), at: CGPoint(x: 0.1, y: 0.5), rects: halves, lanes: both)
expect(swapped == .swap(.terminal), "dragging past the edge onto a neighbor still swaps instead of bouncing back")
print("PASS: categories snap into place; \(checks) total model checks")

var pinned = Settings(); pinned.placedWindows = ["1629-123", "1627-456"]
let pinnedBack = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(pinned))
expect(pinnedBack.placedWindows == ["1629-123", "1627-456"], "windows you placed yourself are remembered across restarts")
expect(Settings().placedWindows.isEmpty, "nothing is pinned on a fresh install")
print("PASS: your placements win; \(checks) total model checks")

let myGrid: [String: ZoneRect] = [
    "terminal": ZoneRect(CGRect(x: 0, y: 0, width: 0.22, height: 0.5)), "desktop": ZoneRect(CGRect(x: 0, y: 0.5, width: 0.22, height: 0.5)),
    "browser": ZoneRect(CGRect(x: 0.22, y: 0, width: 0.47, height: 1)), "messaging": ZoneRect(CGRect(x: 0.84, y: 0, width: 0.16, height: 1)),
    Settings.browserTwo.id: ZoneRect(CGRect(x: 0.69, y: 0, width: 0.15, height: 1)),
]
let myLanes: [Lane] = [.terminal, .desktop, .messaging, .browser, Settings.browserTwo.lane]
expect(GridColumns.columns(rects: myGrid, lanes: myLanes) == [[.terminal, .desktop], [.browser], [Settings.browserTwo.lane], [.messaging]], "Categories mirror the grid: Terminal over Desktop, then Browser, Browser 2, Messaging")
let topSpan: [String: ZoneRect] = ["preview": ZoneRect(CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)), "desktop": ZoneRect(CGRect(x: 0.5, y: 0.5, width: 0.25, height: 0.5)), "messaging": ZoneRect(CGRect(x: 0.75, y: 0.5, width: 0.25, height: 0.5)), "terminal": ZoneRect(CGRect(x: 0, y: 0, width: 0.5, height: 1))]
expect(GridColumns.columns(rects: topSpan, lanes: [.terminal, .preview, .desktop, .messaging]) == [[.terminal], [.preview, .desktop, .messaging]], "a wide box above two smaller ones stays in one column, top first")
print("PASS: categories laid out like the grid; \(checks) total model checks")


// A full ultrawide setup, used by the display tests above.
extension Settings {
    static let browserTwo = CustomCategory(id: "custom:6B3F1E52-4C1D-4A8E-9F21-0B5A2C7D3E01", name: "Browser 2")
    static let terminalTwo = CustomCategory(id: "custom:9D2A7C14-5E3B-4F60-8A91-3C6E0F2B4D02", name: "Terminal 2")
    static var sampleDesk: Settings {
        var s = Settings.firstRun
        s.customCategories = [browserTwo, terminalTwo]
        s.customRects = [
            Lane.terminal.rawValue: ZoneRect(CGRect(x: 0, y: 0, width: 0.22, height: 1)),
            Lane.messaging.rawValue: ZoneRect(CGRect(x: 0.22, y: 0, width: 0.22, height: 1)),
            Lane.browser.rawValue: ZoneRect(CGRect(x: 0.44, y: 0, width: 0.32, height: 1)),
            browserTwo.id: ZoneRect(CGRect(x: 0.76, y: 0, width: 0.24, height: 0.7)),
            terminalTwo.id: ZoneRect(CGRect(x: 0.76, y: 0.7, width: 0.24, height: 0.3)),
        ]
        s.capacities = [Lane.terminal.rawValue: 2, Lane.browser.rawValue: 1, Lane.messaging.rawValue: 1, browserTwo.id: 1, terminalTwo.id: 1]
        s.hiddenLanes = [Lane.simulator, .preview, .desktop, .media].map(\.rawValue)
        return s
    }
}
for (id, name) in [("com.adobe.PremierePro.25", "Adobe Premiere Pro 2025"), ("com.adobe.AfterEffects", "Adobe After Effects 2025"), ("com.apple.iMovieApp", "iMovie"), ("com.apple.FinalCut", "Final Cut Pro"), ("com.blackmagic-design.DaVinciResolve", "DaVinci Resolve"), ("com.lemon.lvoverseas", "CapCut"), ("com.apple.motionapp", "Motion")] {
    expect(Classifier.lane(bundleID: id, appName: name, title: "", rules: [:]) == .preview, "\(name) goes in Previews with the other video apps")
}
print("PASS: new installs start with Browser alone; video editors share one category; \(checks) total model checks")
