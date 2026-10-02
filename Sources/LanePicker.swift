import SwiftUI
import AppKit

struct LaneWindowStrip: NSViewRepresentable {
    @ObservedObject var manager: WindowManager
    let lane: Lane
    let showBoard: () -> Void
    func makeNSView(context: Context) -> LaneScrollHostingView {
        let view = LaneScrollHostingView(rootView: AnyView(Color.clear))
        view.visibility.floor = manager.settings.stripPlacement == .onWindows ? 0.35 : 0
        view.setStripContent(AnyView(LanePickerContent(manager: manager, lane: lane, showBoard: showBoard)))
        view.onSwitch = { delta in manager.cycleWindow(lane, delta: delta) }
        view.onHover = { active in
            if active { manager.hoveredLane = lane }
            else if manager.hoveredLane == lane { manager.hoveredLane = nil }
            manager.stripHovered(lane, active)
        }
        return view
    }
    func updateNSView(_ view: LaneScrollHostingView, context: Context) {
        view.visibility.floor = manager.settings.stripPlacement == .onWindows ? 0.35 : 0
        view.setStripContent(AnyView(LanePickerContent(manager: manager, lane: lane, showBoard: showBoard)))
        view.onSwitch = { delta in manager.cycleWindow(lane, delta: delta) }
        view.onHover = { active in
            if active { manager.hoveredLane = lane }
            else if manager.hoveredLane == lane { manager.hoveredLane = nil }
            manager.stripHovered(lane, active)
        }
    }
}
struct LanePickerContent: View {
    @ObservedObject var manager: WindowManager
    let lane: Lane
    let showBoard: () -> Void
    @State private var dropTargetID: String?
    var style: WindowStripStyle { manager.settings.stripStyle(lane) }
    var scale: Double { manager.settings.windowStripScale }
    var body: some View {
        strip.contextMenu {
            Button("Open Lanes") { showBoard() }
            WindowCountMenu(manager: manager, lane: lane)
            if manager.settings.stripPositions[lane.rawValue] != nil { Button("Move strip back to the top edge") { manager.resetStripPosition(lane) } }
            Divider()
            Button("Use default strip style") { manager.settings.categoryStripStyles.removeValue(forKey: lane.rawValue); manager.stripAppearanceChanged() }
            ForEach(WindowStripStyle.allCases) { choice in
                Button { manager.settings.categoryStripStyles[lane.rawValue] = choice.rawValue; manager.stripAppearanceChanged() } label: {
                    if style == choice { Label(choice.title, systemImage: "checkmark") } else { Text(choice.title) }
                }
            }
        }
    }
    var expanded: Bool { style == .detailed || (style == .expanding && manager.expandedStrip == lane) }
    // One rounded bar for every style. The name and pane chooser always sit at
    // the left edge and only the right part changes, so nothing under the mouse
    // moves when an Expand-on-hover strip grows. The row is laid out once at its
    // final width and the growing bar reveals it, so text never reflows mid-animation.
    var strip: some View {
        HStack(spacing: 6 * scale) {
            moveHandle
            Image(systemName: lane.symbol).foregroundStyle(lane.color)
            Text(manager.name(lane)).font(.system(size: 10 * scale, weight: .semibold)).foregroundStyle(lane.color).lineLimit(1).fixedSize()
            slotPicker
            ZStack(alignment: .leading) {
                indicators(light: false).opacity(expanded ? 0 : 1).allowsHitTesting(!expanded)
                chipRow.opacity(expanded ? 1 : 0).allowsHitTesting(expanded)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.18), value: expanded)
        }.padding(.horizontal, 12 * scale).font(.system(size: 10 * scale))
            .frame(width: manager.displayedStripMetrics(lane).width, height: manager.displayedStripMetrics(lane).height, alignment: .leading)
            // The bar follows the panel's live width; the wider row is clipped by
            // the capsule, so the right end stays round while it grows.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .leading)
            .background(surface.opacity(0.98)).clipShape(Capsule())
            .overlay(Capsule().strokeBorder(lane.color.opacity(0.25)))
            .foregroundStyle(ink).preferredColorScheme(.dark)
    }
    @ViewBuilder var moveHandle: some View {
        if manager.settings.stripPlacement == .onWindows {
            Image(systemName: "line.3.horizontal").font(.system(size: 9 * scale, weight: .semibold)).foregroundStyle(ink.opacity(0.45))
                .frame(width: 14 * scale, height: 24 * scale)
                .overlay(NativeMoveGrip { frame, phase in
                    switch phase {
                    case .began: manager.draggingStrip = lane
                    case .changed: break
                    case .ended:
                        manager.draggingStrip = nil
                        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
                        manager.moveStrip(lane, to: CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height))
                    }
                })
                .help("Drag to move this strip anywhere. Right-click the strip to move it back.")
        }
    }
    func indicators(light: Bool) -> some View {
        let all = manager.items(lane)
        let active = manager.activeWindow(lane)
        let selectedIndex = all.firstIndex { $0.id == active?.id } ?? 0
        let indices = Layout.pickerIndices(total: all.count, active: selectedIndex, limit: 16)
        return HStack(spacing: 0) {
            if all.isEmpty { Circle().fill(Color.gray.opacity(0.4)).frame(width: 5 * scale, height: 5 * scale) }
            ForEach(Array(indices), id: \.self) { index in
                let window = all[index]
                let selected = window.id == active?.id
                Button { manager.reveal(window) } label: {
                    Capsule().fill(selected ? (light ? Color(red: 0.21, green: 0.31, blue: 0.22) : lane.color) : (light ? Color(red: 0.68, green: 0.75, blue: 0.67) : Color.white.opacity(0.25)))
                        .frame(width: (selected ? 16 : 4) * scale, height: 5 * scale)
                        .frame(width: (selected ? 18 : 11) * scale, height: 26 * scale)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .help("\(index + 1)/\(all.count) · \(window.appName) — \(window.title)\nClick to show; Scroll or use Left/Right to switch; 1–9 / 0 selects a tab.")
                    .accessibilityLabel("Show \(window.appName): \(window.title)")
                    .accessibilityValue(selected ? "Selected" : "")
                    .draggable("tab:" + window.id)
                    .dropDestination(for: String.self) { values, point in return manager.reorderTab(values, before: window, after: point.x > (selected ? 18 : 11) * scale / 2) } isTargeted: { active in dropTargetID = active ? window.id : (dropTargetID == window.id ? nil : dropTargetID) }
                    .contextMenu { tabMenu(window) }
                    .overlay { if dropTargetID == window.id { RoundedRectangle(cornerRadius: 3).strokeBorder(lane.color, lineWidth: 1).allowsHitTesting(false) } }
            }
        }
    }
    @ViewBuilder var slotPicker: some View {
        let slots = manager.slotIDs(lane)
        if slots.count == 2 {
            HStack(spacing: 3 * scale) {
                ForEach(Array(slots.indices), id: \.self) { index in
                    Button { manager.selectSlot(lane, index: index) } label: {
                        Text(manager.slotLabel(lane, index: index))
                            .font(.system(size: 9 * scale, weight: .semibold)).lineLimit(1)
                            .padding(.horizontal, 5 * scale).padding(.vertical, 4 * scale)
                            .foregroundStyle((manager.activeSlot[lane] ?? 0) == index ? lane.color : ink.opacity(0.6))
                            .background((manager.activeSlot[lane] ?? 0) == index ? lane.color.opacity(0.16) : Color.clear)
                            .clipShape(Capsule())
                    }.buttonStyle(.plain).fixedSize()
                        .onHover { hovering in if hovering { manager.targetSlot(lane, index: index) } }
                        .help("\(manager.slotLabel(lane, index: index)): \(manager.items(lane).first(where: { $0.id == slots[index] }).map(manager.windowLabel) ?? "Empty")\nHover to target this pane, then scroll or use Left/Right / 1–9 / 0. The other pane stays fixed.")
                }
            }
        } else if slots.count > 2 {
            Menu {
                ForEach(Array(slots.indices), id: \.self) { index in
                    Button("\(manager.slotLabel(lane, index: index)) · \(manager.items(lane).first(where: { $0.id == slots[index] }).map(manager.windowLabel) ?? "Empty")") { manager.selectSlot(lane, index: index) }
                }
            } label: {
                HStack(spacing: 2) { Text("\((manager.activeSlot[lane] ?? 0) + 1)"); Image(systemName: "chevron.down").font(.system(size: 6 * scale)) }
                    .font(.system(size: 9 * scale, weight: .medium))
            }.menuStyle(.borderlessButton).fixedSize()
                .help("Target \(manager.slotLabel(lane, index: manager.activeSlot[lane] ?? 0)). Switching this slot keeps the other windows fixed.")
        }
    }
    @ViewBuilder func tabMenu(_ window: ManagedWindow) -> some View {
        Button("Rename tab…") { manager.beginRenamingWindow(window) }
        Button("Show window") { manager.reveal(window) }
        if manager.settings.capacity(lane) > 1 {
            ForEach(Array(manager.slotIDs(lane).indices), id: \.self) { index in
                Button("Show in \(manager.slotLabel(lane, index: index))") { manager.selectSlot(lane, index: index); manager.reveal(window) }
            }
        }
        Divider()
        Button("Open Lanes") { showBoard() }
    }
    // Window names as pill chips, with the counter at the right end.
    var chipRow: some View {
        let all = manager.items(lane)
        let active = manager.activeWindow(lane)
        let selectedIndex = all.firstIndex { $0.id == active?.id } ?? 0
        let indices = Layout.pickerIndices(total: all.count, active: selectedIndex, limit: 16)
        let reserved = WindowStripMetrics.chipRoom(slots: manager.slotIDs(lane).count) * scale
        let chipWidth = min(WindowStripMetrics.chipWidth * scale, max(36, (manager.displayedStripMetrics(lane).width - reserved) / Double(max(1, indices.count))))
        return HStack(spacing: 4 * scale) {
            ForEach(Array(indices), id: \.self) { index in
                let window = all[index]
                let selected = window.id == active?.id
                Button { manager.reveal(window) } label: {
                    HStack(spacing: 3 * scale) {
                        if let icon = window.icon { Image(nsImage: icon).resizable().frame(width: 11 * scale, height: 11 * scale) }
                        Text(manager.windowLabel(window)).font(.system(size: 9 * scale, weight: selected ? .semibold : .regular)).lineLimit(1).truncationMode(.tail)
                    }.padding(.horizontal, 7 * scale).padding(.vertical, 3 * scale)
                        .frame(maxWidth: chipWidth)
                        .foregroundStyle(selected ? lane.color : ink.opacity(0.75))
                        .background(selected ? lane.color.opacity(0.18) : Color.white.opacity(0.06)).clipShape(Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(.plain).help("\(index + 1)/\(all.count) · \(window.appName) — \(window.title)\nClick to show; hover + Scroll or use Left/Right to switch; 1–9 / 0 selects a tab.")
                    .accessibilityLabel("Show \(window.appName): \(window.title)")
                    .accessibilityValue(selected ? "Selected" : "")
                    .draggable("tab:" + window.id)
                    .dropDestination(for: String.self) { values, point in return manager.reorderTab(values, before: window, after: point.x > chipWidth / 2) } isTargeted: { active in dropTargetID = active ? window.id : (dropTargetID == window.id ? nil : dropTargetID) }
                    .contextMenu { tabMenu(window) }
                    .overlay { if dropTargetID == window.id { Capsule().strokeBorder(lane.color, lineWidth: 1).allowsHitTesting(false) } }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4 * scale) {
                Button { manager.cycleWindow(lane, delta: -1) } label: { Image(systemName: "chevron.left") }.disabled(all.count < 2)
                Text(manager.windowCounter(lane)).font(.system(size: 9 * scale, design: .monospaced)).foregroundStyle(lane.color).fixedSize()
                Button { manager.cycleWindow(lane) } label: { Image(systemName: "chevron.right") }.disabled(all.count < 2)
            }.buttonStyle(.plain).fixedSize()
        }
    }
}
