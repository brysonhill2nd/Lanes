import SwiftUI
import AppKit

private struct EditorFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct GridEditor: View {
    @ObservedObject var manager: WindowManager
    @State private var swapMode = false
    @State private var showNewCategory = false
    @State private var frames: [String: CGRect] = [:]
    @State private var draggingLane: Lane?
    @State private var overShelf = false
    @State private var nativeShelfTarget = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("Drag behavior", selection: $swapMode) {
                    Text("Move & resize").tag(false)
                    Text("Swap categories").tag(true)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 255)
                Toggle("Snap to grid", isOn: Binding(get: { manager.settings.snapToGrid }, set: { manager.settings.snapToGrid = $0; manager.save() }))
                    .toggleStyle(.checkbox).font(.system(size: 11)).fixedSize()
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                Button("Undo grid edit") { manager.editGrid { manager.undoLayout() } }.disabled(manager.layoutHistory.isEmpty).font(.system(size: 11))
                Menu("Add category") {
                    Button("New named category…") { showNewCategory = true }
                    Divider()
                    ForEach(manager.availableLanes.filter { !manager.gridLanes.contains($0) }) { lane in
                        Button(manager.name(lane)) { manager.editGrid { manager.restoreCategory(lane) } }
                    }
                }.font(.system(size: 11))
                Menu {
                    Button("Split left / right") { manager.editGrid { manager.splitCategory(manager.selectedLane, sideBySide: true) } }
                    Button("Split top / bottom") { manager.editGrid { manager.splitCategory(manager.selectedLane, sideBySide: false) } }
                } label: { Label("Split", systemImage: "scissors") }.font(.system(size: 11))
                    .help("Cut this category into two independent places, then move or resize each")
                MoveWindowMenu(manager: manager, lane: manager.selectedLane)
                Spacer(minLength: 0)
            }
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        for x in 0...32 {
                            for y in 0...16 {
                                let point = CGPoint(x: CGFloat(x) * size.width / 32, y: CGFloat(y) * size.height / 16)
                                context.fill(Path(ellipseIn: CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)), with: .color(.white.opacity(0.10)))
                            }
                        }
                    }.allowsHitTesting(false)
                    ForEach(manager.gridLanes) { lane in
                        EditableCategory(manager: manager, lane: lane, area: proxy.size, swapMode: swapMode, onDrag: { point in
                            draggingLane = lane
                            let origin = frames["grid"]?.origin ?? .zero
                            overShelf = frames["shelf"]?.contains(CGPoint(x: point.x + origin.x, y: point.y + origin.y)) ?? false
                        }, onEndDrag: { point in
                            let origin = frames["grid"]?.origin ?? .zero
                            let shelve = frames["shelf"]?.contains(CGPoint(x: point.x + origin.x, y: point.y + origin.y)) ?? false
                            draggingLane = nil; overShelf = false
                            if shelve { manager.editGrid { _ = manager.receiveShelfDrop(["lane:" + lane.rawValue]) } }
                            return shelve
                        })
                    }
                    if let hint = manager.snapHint { SnapHintLayer(manager: manager, hint: hint, size: proxy.size) }
                    if let preview = manager.presetPreview { PresetPreviewLayer(manager: manager, preview: preview, size: proxy.size) }
                }.frame(width: proxy.size.width, height: proxy.size.height)
                    .coordinateSpace(name: "categoryGrid")
                    .clipped()
                    .background(Color.black.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.07)).allowsHitTesting(false))
                    .dropDestination(for: String.self) { values, point in var placed = false; manager.editGrid { placed = manager.receiveWorkspaceDrop(values, at: point, in: proxy.size) }; return placed }
                    .background(GeometryReader { geometry in Color.clear.preference(key: EditorFrameKey.self, value: ["grid": geometry.frame(in: .named("categoryWorkspace"))]) })
            }.frame(height: 330)
            categoryShelf
            CategoryInspector(manager: manager)
            Text(swapMode ? "Drag categories to swap regions, or into the shelf to remove them. Drag a shelf category back into the workspace to restore it." : "Drag edges to resize, the center to move, or drag a category into the shelf to remove it. Drag it back to restore it. Backspace also removes the selected section.")
                .font(.system(size: 10)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
        }.coordinateSpace(name: "categoryWorkspace")
            .onPreferenceChange(EditorFrameKey.self) { frames = $0 }
            .sheet(isPresented: $showNewCategory) { NewCategoryView(manager: manager) }
    }
    var categoryShelf: some View {
        let targeted = overShelf || nativeShelfTarget
        let removed = manager.availableLanes.filter { !manager.gridLanes.contains($0) }
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Category shelf", systemImage: "tray").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(targeted ? (manager.gridLanes.count > 1 ? "Release to remove from workspace" : "Keep one category in the workspace") : "Drag out to remove · drag back to restore")
                    .font(.system(size: 10)).foregroundStyle(targeted ? accent : muted)
            }
            if removed.isEmpty {
                Text(draggingLane.map { "Move \(manager.name($0)) here" } ?? "Drop a workspace category here. Its name and app assignments are kept.")
                    .font(.system(size: 11)).foregroundStyle(muted).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(removed) { lane in
                            Label(manager.name(lane), systemImage: lane.symbol).font(.system(size: 11, weight: .medium))
                                .foregroundStyle(lane.color).padding(.horizontal, 12).padding(.vertical, 9)
                                .background(lane.color.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 6))
                                .draggable("lane:" + lane.rawValue)
                                .help("Drag into the workspace to restore \(manager.name(lane))")
                                .contextMenu { Button("Restore to workspace") { manager.editGrid { manager.restoreCategory(lane) } }; Button("Rename category…") { manager.renameTarget = lane } }
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(targeted ? accent.opacity(0.10) : Color.white.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targeted ? accent : Color.white.opacity(0.10), style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: [5, 4])))
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { values, _ in var removed = false; manager.editGrid { removed = manager.receiveShelfDrop(values) }; return removed } isTargeted: { nativeShelfTarget = $0 }
            .background(GeometryReader { geometry in Color.clear.preference(key: EditorFrameKey.self, value: ["shelf": geometry.frame(in: .named("categoryWorkspace"))]) })
    }
}

// The bottom of the Lanes window: everything that has no place in your grid yet
// on the left, and every category in your grid with its windows or apps on the
// right. Drag something onto a category, or use its menu, which lists only the
// categories in your grid. Windows move right away.
struct CategoryBoard: View {
    @ObservedObject var manager: WindowManager
    @State private var target: Lane?
    @State private var outsideTargeted = false
    @State private var byWindow: Bool
    init(manager: WindowManager, byWindow: Bool = true) { self.manager = manager; _byWindow = State(initialValue: byWindow) }
    var gridLanes: [Lane] { manager.enabledLanes }
    // One row per app, even when an app runs more than once.
    var apps: [RunningAppSummary] {
        var seen: Set<String> = []
        return manager.runningApps.filter { seen.insert($0.bundleID).inserted }
    }
    var outsideApps: [RunningAppSummary] { apps.filter { !gridLanes.contains($0.lane) } }
    var outsideWindows: [ManagedWindow] { manager.outsideGrid.filter { !$0.minimized } }
    func apps(in lane: Lane) -> [RunningAppSummary] { apps.filter { $0.lane == lane } }
    func automatic(_ app: RunningAppSummary) -> Lane { Classifier.lane(bundleID: app.bundleID, appName: app.name, title: "", rules: [:]) }
    // Laid out like your grid on the screen.
    var stacks: [[Lane]] {
        let rects = Dictionary(uniqueKeysWithValues: gridLanes.map { ($0.rawValue, ZoneRect(manager.settings.unitRect(for: $0))) })
        return GridColumns.columns(rects: rects, lanes: gridLanes)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("CATEGORIES").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(muted)
                Spacer()
                Picker("Show", selection: $byWindow) { Text("Windows").tag(true); Text("Apps").tag(false) }.labelsHidden().pickerStyle(.segmented).frame(width: 170)
            }
            Text(byWindow ? "Drag any window onto a category and it moves there right away; drag it back to the left to undo. One Arc window for videos, a terminal, Spotify and ChatGPT can share a category. To place one browser or terminal tab, first make it its own window (drag the tab out in Arc, or Window › Move Tab to New Window in Ghostty)."
                 : "Drag an app onto a category and every window of that app moves there; drag it back to the left to undo.")
                .font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    heading("NOT IN YOUR GRID", count: byWindow ? outsideWindows.count : outsideApps.count)
                    if byWindow {
                        if outsideWindows.isEmpty { empty("Every open window has a category in your grid.") }
                        ForEach(outsideWindows) { window in windowRow(window) }
                    } else {
                        if outsideApps.isEmpty { empty("Every running app has a category in your grid.") }
                        ForEach(outsideApps) { app in appRow(app, note: "Usually \(manager.name(automatic(app)))\(gridLanes.contains(automatic(app)) ? "" : " · shelved")") }
                    }
                }
                .padding(8)
                .frame(width: 266, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(outsideTargeted ? 0.07 : 0)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(outsideTargeted ? 0.3 : 0), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                // Dropping here undoes a choice: the window or app goes back to its usual category.
                .dropDestination(for: String.self) { values, _ in unassign(values) } isTargeted: { outsideTargeted = $0 }
                Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(stacks.enumerated()), id: \.offset) { _, stack in
                        VStack(spacing: 10) { ForEach(stack) { lane in section(lane) } }.frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
        }
        .foregroundStyle(ink)
    }
    func heading(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(muted)
            Text("\(count)").font(.system(size: 9, design: .monospaced)).foregroundStyle(muted)
        }
    }
    func empty(_ text: String) -> some View { Text(text).font(.system(size: 11)).foregroundStyle(muted).padding(.vertical, 12) }
    func section(_ lane: Lane) -> some View {
        let windows = manager.items(lane), list = apps(in: lane)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: lane.symbol).foregroundStyle(lane.color)
                Text(manager.name(lane)).font(.system(size: 12, weight: .semibold)).foregroundStyle(lane.color)
                Text("\(byWindow ? windows.count : list.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                Spacer()
            }
            if byWindow {
                if windows.isEmpty { Text("Drop a window here").font(.system(size: 10)).foregroundStyle(muted).padding(.vertical, 6) }
                ForEach(windows) { window in windowRow(window, inFront: manager.visibleItems(lane).contains { $0.id == window.id }) }
            } else {
                if list.isEmpty { Text("Drop an app here").font(.system(size: 10)).foregroundStyle(muted).padding(.vertical, 6) }
                ForEach(list) { app in appRow(app) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(lane.color.opacity(target == lane ? 0.14 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(lane.color.opacity(target == lane ? 0.6 : 0.18)))
        .dropDestination(for: String.self) { values, _ in assign(values, to: lane) } isTargeted: { on in target = on ? lane : (target == lane ? nil : target) }
    }
    func appRow(_ app: RunningAppSummary, note: String? = nil) -> some View {
        HStack(spacing: 8) {
            grip
            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.system(size: 12)).lineLimit(1)
                if let note { Text(note).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1) }
            }
            Spacer(minLength: 4)
            Menu {
                ForEach(gridLanes) { lane in
                    Button { manager.assignApp(app, to: lane) } label: {
                        if app.lane == lane { Label(manager.name(lane), systemImage: "checkmark") } else { Text(manager.name(lane)) }
                    }
                }
                if manager.settings.appRules[app.bundleID] != nil { Divider(); Button("Use automatic category") { manager.resetAppRule(app) } }
            } label: { Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(muted) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Choose a category")
        }
        .modifier(DragRow())
        .draggable("app:" + app.bundleID) { dragPreview(app.name, icon: app.icon) }
    }
    func windowRow(_ window: ManagedWindow, inFront: Bool = false) -> some View {
        HStack(spacing: 8) {
            grip
            if let icon = window.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if inFront { Circle().fill(window.lane.color).frame(width: 5, height: 5).help("In front right now") }
                    Text(manager.windowLabel(window)).font(.system(size: 12)).lineLimit(1)
                }
                Text(window.appName).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                ForEach(gridLanes) { lane in
                    Button { manager.moveWindow(window, to: lane) } label: {
                        if window.lane == lane && manager.windows.contains(where: { $0.id == window.id }) { Label(manager.name(lane), systemImage: "checkmark") } else { Text(manager.name(lane)) }
                    }
                }
                Divider()
                Button("Show window") { manager.reveal(window) }
                Button("Rename tab…") { manager.beginRenamingWindow(window) }
            } label: { Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(muted) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Choose a category, show the window, or rename its tab")
        }
        .modifier(DragRow())
        .help(window.title)
        .draggable("lanewindow:" + window.id) { dragPreview(manager.windowLabel(window), icon: window.icon) }
    }
    var grip: some View { Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(muted.opacity(0.7)).frame(width: 10) }
    func dragPreview(_ title: String, icon: NSImage?) -> some View {
        HStack(spacing: 6) {
            if let icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }.padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(surface)).overlay(Capsule().strokeBorder(accent.opacity(0.6))).foregroundStyle(ink)
    }
    func unassign(_ values: [String]) -> Bool {
        if let value = values.first(where: { $0.hasPrefix("lanewindow:") }), let window = manager.windows.first(where: { $0.id == String(value.dropFirst(11)) }) {
            manager.clearWindowCategory(window); return true
        }
        if let value = values.first(where: { $0.hasPrefix("app:") }), let app = manager.runningApps.first(where: { $0.bundleID == String(value.dropFirst(4)) }) {
            manager.resetAppRule(app); return true
        }
        return false
    }
    func assign(_ values: [String], to lane: Lane) -> Bool {
        if let value = values.first(where: { $0.hasPrefix("lanewindow:") }) {
            let id = String(value.dropFirst(11))
            guard let window = manager.windows.first(where: { $0.id == id }) ?? manager.outsideGrid.first(where: { $0.id == id }) else { return false }
            manager.moveWindow(window, to: lane)
            return true
        }
        guard let value = values.first(where: { $0.hasPrefix("app:") }),
              let app = manager.runningApps.first(where: { $0.bundleID == String(value.dropFirst(4)) }) else { return false }
        manager.assignApp(app, to: lane)
        return true
    }
}

struct EditableCategory: View {
    @ObservedObject var manager: WindowManager
    let lane: Lane
    let area: CGSize
    let swapMode: Bool
    let onDrag: (CGPoint) -> Void
    let onEndDrag: (CGPoint) -> Bool
    @State private var start: CGRect?
    @State private var candidate: CGRect?
    @State private var targeted = false
    @State private var resizeStart: [String: ZoneRect]?
    var rect: CGRect { candidate ?? manager.editorRect(lane) }
    @State private var point: CGPoint = .zero
    @State private var resizing = false
    // Red only when the drop could not be placed at all.
    var invalid: Bool {
        guard let candidate else { return false }
        if resizing { return !manager.validEdit(lane, rect: candidate) }
        return manager.snapPlan(lane, candidate: candidate, at: point) == .none
    }
    var body: some View {
        let unit = rect
        let frame = Layout.frame(unit: unit, in: CGRect(origin: .zero, size: area), gap: 7)
        let selected = manager.selectedLane == lane
        GeometryReader { inner in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7).fill(lane.color.opacity(selected || targeted ? 0.10 : 0.04))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        HStack(spacing: 5) {
                            Image(systemName: lane.symbol).font(.system(size: 11))
                            Text(manager.name(lane)).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        }.draggable("lane:" + lane.rawValue).help("Drag to the category shelf to remove from workspace")
                        Spacer(minLength: 0)
                        WindowCountMenu(manager: manager, lane: lane, compact: inner.size.width < 300, staged: true)
                    }.foregroundStyle(lane.color)
                    if inner.size.height > 65 {
                        if !manager.trusted {
                            Text("\(manager.apps(lane).count) running apps").font(.system(size: 9)).foregroundStyle(muted).lineLimit(1)
                            if inner.size.height > 105 {
                                Text(manager.apps(lane).prefix(3).map(\.name).joined(separator: " · ")).font(.system(size: 9)).foregroundStyle(lane.color.opacity(0.7)).lineLimit(2)
                            }
                        } else if manager.items(lane).isEmpty {
                            Text("No windows").font(.system(size: 9)).foregroundStyle(muted).lineLimit(1)
                        } else {
                            Text(manager.activeWindow(lane)?.appName ?? "").font(.system(size: 10)).lineLimit(1)
                            if inner.size.height > 105 {
                                Text(manager.windowCounter(lane)).font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                                HStack(spacing: 14) {
                                    Button { manager.cycleWindow(lane, delta: -1) } label: { Image(systemName: "chevron.left") }
                                    Button { manager.cycleWindow(lane) } label: { Image(systemName: "chevron.right") }
                                }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(lane.color)
                            }
                        }
                    }
                }.padding(10).frame(width: inner.size.width, height: inner.size.height, alignment: .topLeading).clipped()
            }.frame(width: inner.size.width, height: inner.size.height).clipped()
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(invalid ? .red : lane.color.opacity(selected ? 0.8 : 0.25), lineWidth: selected || invalid ? 2 : 1))
                .contentShape(Rectangle())
                .onTapGesture { manager.selectGridCategory(lane) }
                .gesture(drag(resize: false))
                .overlay {
                    if !swapMode {
                        ForEach(ResizeEdge.allCases, id: \.self) { edge in
                            grip(edge, size: inner.size)
                        }
                    }
                }
                .dropDestination(for: String.self) { values, _ in
                    guard values.contains(where: { $0.hasPrefix("lane:") }) else { return manager.receiveDrop(values, into: lane) }
                    var placed = false; manager.editGrid { placed = manager.receiveDrop(values, into: lane) }; return placed
                } isTargeted: { targeted = $0 }
                .contextMenu {
                    WindowCountMenu(manager: manager, lane: lane, staged: true)
                    Button("Split left / right") { manager.editGrid { manager.splitCategory(lane, sideBySide: true) } }
                    Button("Split top / bottom") { manager.editGrid { manager.splitCategory(lane, sideBySide: false) } }
                    MoveWindowMenu(manager: manager, lane: lane)
                    Button("Rename category…") { manager.renameTarget = lane }
                    Button("Delete category", role: .destructive) { manager.editGrid { manager.removeCategory(lane) } }.disabled(manager.gridLanes.count <= 1)
                }
        }.frame(width: max(1, frame.width), height: max(1, frame.height)).offset(x: frame.minX, y: frame.minY)
            .zIndex(start == nil ? 0 : 2)
    }
    func grip(_ edge: ResizeEdge, size: CGSize) -> some View {
        let horizontal = edge == .top || edge == .bottom
        let corner = edge == .bottomRight
        let gripWidth = corner ? 24 : horizontal ? max(16, size.width - 32) : 12
        let gripHeight = corner ? 24 : horizontal ? 12 : max(16, size.height - 32)
        let x = edge == .left ? 6 : edge == .right || corner ? size.width - (corner ? 12 : 6) : size.width / 2
        let y = edge == .top ? 6 : edge == .bottom || corner ? size.height - (corner ? 12 : 6) : size.height / 2
        return ZStack {
            if corner {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(lane.color).frame(width: 24, height: 24).background(surface.opacity(0.8)).clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Capsule().fill(lane.color.opacity(0.55)).frame(width: horizontal ? min(36, gripWidth) : 3, height: horizontal ? 3 : min(36, gripHeight))
            }
            NativeResizeGrip(edge: edge) { delta, phase in
                manager.selectGridCategory(lane)
                switch phase {
                case .began: resizeStart = manager.layoutRects()
                case .changed:
                    guard let resizeStart else { return }
                    manager.editorPreview = GridGeometry.resizing(resizeStart, lane: lane, edge: edge,
                        dx: delta.width / area.width, dy: delta.height / area.height, snap: manager.settings.snapToGrid)
                case .ended:
                    guard let resizeStart else { return }
                    let rects = GridGeometry.resizing(resizeStart, lane: lane, edge: edge,
                        dx: delta.width / area.width, dy: delta.height / area.height, snap: manager.settings.snapToGrid)
                    manager.editGrid { manager.commitGridResize(rects, lane: lane) }; self.resizeStart = nil
                }
            }
        }.frame(width: gripWidth, height: gripHeight).position(x: x, y: y)
            .help(corner ? "Resize width and height" : horizontal ? "Drag to change height" : "Drag to change width")
    }
    func drag(resize: Bool) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("categoryGrid"))
            .onChanged { value in
                onDrag(value.location)
                manager.selectGridCategory(lane)
                if start == nil { start = manager.grid.unitRect(for: lane) }
                if !swapMode {
                    candidate = GridGeometry.edited(start!, dx: value.translation.width / area.width, dy: value.translation.height / area.height, resize: resize, snap: manager.settings.snapToGrid)
                    resizing = resize
                    point = CGPoint(x: value.location.x / max(1, area.width), y: value.location.y / max(1, area.height))
                    if !resize, let candidate {
                        let plan = manager.snapPlan(lane, candidate: candidate, at: point)
                        manager.snapHint = { if case .move = plan { return nil }; return .init(lane: lane, plan: plan) }()
                    }
                }
            }
            .onEnded { value in
                manager.snapHint = nil
                if onEndDrag(value.location) { start = nil; candidate = nil; return }
                if swapMode {
                    if let target = manager.category(at: value.location, in: CGRect(origin: .zero, size: area)) { manager.editGrid { manager.swapCategories(lane, target) } }
                } else if let candidate {
                    if resize { manager.editGrid { manager.editCategory(lane, rect: candidate) } }
                    else { manager.editGrid { manager.dropCategory(lane, candidate: candidate, at: CGPoint(x: value.location.x / max(1, area.width), y: value.location.y / max(1, area.height))) } }
                }
                start = nil; candidate = nil
            }
    }
}

struct CategoryInspector: View {
    @ObservedObject var manager: WindowManager
    @State private var x = 0.0
    @State private var y = 0.0
    @State private var width = 0.0
    @State private var height = 0.0
    var body: some View {
        HStack(spacing: 12) {
            Label(manager.name(manager.selectedLane), systemImage: manager.selectedLane.symbol)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(manager.selectedLane.color).frame(width: 115, alignment: .leading)
            number("X", $x); number("Y", $y); number("Width", $width); number("Height", $height)
            Button("Apply") { apply() }.font(.system(size: 11))
            Spacer(minLength: 0)
            Button { manager.editGrid { manager.removeCategory(manager.selectedLane) } } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(muted).disabled(manager.gridLanes.count <= 1).help("Delete selected category")
        }.padding(12).background(Color.white.opacity(0.025)).clipShape(RoundedRectangle(cornerRadius: 7))
            .onAppear { load() }
            .onChange(of: manager.selectedLane) { _, _ in load() }
            .onChange(of: manager.editorRect(manager.selectedLane)) { _, _ in load() }
    }
    func number(_ label: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label + " %").font(.system(size: 9)).foregroundStyle(muted)
            TextField(label, value: value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).frame(width: 66).font(.system(size: 11, design: .monospaced)).onSubmit { apply() }
        }
    }
    func load() {
        let rect = manager.editorRect(manager.selectedLane)
        x = rect.minX * 100; y = rect.minY * 100; width = rect.width * 100; height = rect.height * 100
    }
    func apply() {
        manager.editGrid { manager.editCategory(manager.selectedLane, rect: CGRect(x: x / 100, y: y / 100, width: width / 100, height: height / 100)) }
    }
}

struct NewCategoryView: View {
    @ObservedObject var manager: WindowManager
    @Environment(\.dismiss) private var dismiss
    var renameLane: Lane? = nil
    @State private var categoryName = ""
    @State private var error = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(renameLane == nil ? "Create a category" : "Rename category").font(.system(size: 21, weight: .medium))
            Text("Give a group of windows its own place in your grid.").font(.system(size: 12)).foregroundStyle(muted)
            TextField("Name, e.g. Research or Music", text: $categoryName).textFieldStyle(.roundedBorder).focused($focused).onSubmit { create() }
            if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button(renameLane == nil ? "Create" : "Rename") { create() }.keyboardShortcut(.defaultAction).disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(28).frame(width: 420).background(surface).preferredColorScheme(.dark).onAppear { if let renameLane { categoryName = manager.name(renameLane) }; focused = true }
    }
    func create() { if let renameLane { manager.renameCategory(renameLane, name: categoryName); dismiss() } else if ({ var added = false; manager.editGrid { added = manager.addCategory(name: categoryName) }; return added })() { dismiss() } else { error = manager.status } }
}

struct MoveWindowMenu: View {
    @ObservedObject var manager: WindowManager
    let lane: Lane
    var body: some View {
        Menu {
            let candidates = manager.windows.filter { $0.lane != lane }
            let outside = manager.outsideGrid.filter { !$0.minimized }
            if candidates.isEmpty && outside.isEmpty { Text("No other open windows") }
            ForEach(candidates) { window in
                Button("\(window.appName) · \(manager.windowLabel(window))") { manager.moveWindow(window, to: lane) }
            }
            if !outside.isEmpty {
                Section("Not in any category") {
                    ForEach(outside) { window in
                        Button("\(window.appName) · \(manager.windowLabel(window))") { manager.moveWindow(window, to: lane) }
                    }
                }
            }
            Divider()
            Button("Refresh open windows") { manager.refresh(silent: true) }
        } label: { Label("Move window here", systemImage: "plus.rectangle.on.rectangle") }
            .font(.system(size: 11)).disabled(!manager.trusted)
    }
}

struct WindowCountMenu: View {
    @ObservedObject var manager: WindowManager
    let lane: Lane
    var compact = false
    var staged = false   // in the grid editor: part of the draft until Apply
    var body: some View {
        Menu {
            ForEach(1...4, id: \.self) { count in
                Button {
                    manager.selectGridCategory(lane)
                    if staged { manager.editGrid { manager.setCapacity(lane, count) } } else { manager.setCapacity(lane, count) }
                } label: {
                    let title = "Show \(count) window\(count == 1 ? "" : "s") at once"
                    if (staged ? manager.grid : manager.settings).capacity(lane) == count { Label(title, systemImage: "checkmark") }
                    else { Text(title) }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "rectangle.split.2x2")
                Text(compact ? "\((staged ? manager.grid : manager.settings).capacity(lane))" : "\((staged ? manager.grid : manager.settings).capacity(lane)) window\((staged ? manager.grid : manager.settings).capacity(lane) == 1 ? "" : "s")")
            }.font(.system(size: 9, weight: .medium)).lineLimit(1)
        }.menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("Windows shown at once in \(manager.name(lane))")
            .accessibilityValue("\((staged ? manager.grid : manager.settings).capacity(lane))")
            .help("Choose how many windows appear together in \(manager.name(lane)). Other windows remain in its stack. Only this region changes.")
    }
}

// A preset drawn in place of the grid. It cannot be edited; Apply or Cancel above it.
struct PresetPreviewLayer: View {
    @ObservedObject var manager: WindowManager
    let preview: WindowManager.PresetPreview
    let size: CGSize
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(surface)
            ForEach(preview.lanes) { lane in
                if let r = preview.rects[lane.rawValue]?.cgRect {
                    let frame = CGRect(x: r.minX * size.width + 3, y: r.minY * size.height + 3, width: max(0, r.width * size.width - 6), height: max(0, r.height * size.height - 6))
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: lane.symbol).foregroundStyle(lane.color)
                            Text(manager.name(lane)).font(.system(size: 11, weight: .semibold)).foregroundStyle(lane.color).lineLimit(1)
                        }
                        Text(manager.gridLanes.contains(lane) || manager.enabledLanes.contains(lane) ? (manager.items(lane).count == 1 ? "1 window" : "\(manager.items(lane).count) windows") : "not in your grid now").font(.system(size: 10)).foregroundStyle(muted)
                    }
                    .padding(10)
                    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(lane.color.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(lane.color.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    .offset(x: frame.minX, y: frame.minY)
                }
            }
            Text("PREVIEW").font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(surface)
                .padding(.horizontal, 8).padding(.vertical, 3).background(accent).clipShape(Capsule())
                .offset(x: size.width - 74, y: 8)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle()).onTapGesture {}
    }
}

// While a category is dragged: the category it would swap with, or the free
// space it would fill.
struct SnapHintLayer: View {
    @ObservedObject var manager: WindowManager
    let hint: WindowManager.SnapHint
    let size: CGSize
    var body: some View {
        Group {
            switch hint.plan {
            case .swap(let target): mark(manager.editorRect(target), label: "Swap with \(manager.name(target))", dashed: false)
            case .fit(let rects): if let r = rects[hint.lane.rawValue]?.cgRect { mark(r, label: "Fits here", dashed: true) }
            default: EmptyView()
            }
        }.allowsHitTesting(false)
    }
    func mark(_ r: CGRect, label: String, dashed: Bool) -> some View {
        let frame = CGRect(x: r.minX * size.width + 3, y: r.minY * size.height + 3, width: max(0, r.width * size.width - 6), height: max(0, r.height * size.height - 6))
        return ZStack {
            RoundedRectangle(cornerRadius: 7).fill(accent.opacity(0.10))
            RoundedRectangle(cornerRadius: 7).strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: dashed ? [6, 4] : []))
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(surface)
                .padding(.horizontal, 10).padding(.vertical, 4).background(accent).clipShape(Capsule())
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
    }
}

// A row you can pick up: open-hand cursor and a highlight on hover.
struct DragRow: ViewModifier {
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(hovered ? 0.08 : 0.035)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(hovered ? 0.14 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onHover { inside in
                hovered = inside
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
    }
}
