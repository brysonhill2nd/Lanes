import SwiftUI
import UniformTypeIdentifiers

extension Lane {
    var color: Color {
        switch self {
        case .terminal: return Color(red: 0.70, green: 0.82, blue: 0.56)
        case .simulator: return Color(red: 0.63, green: 0.73, blue: 0.94)
        case .preview: return Color(red: 0.91, green: 0.68, blue: 0.49)
        case .browser: return Color(red: 0.64, green: 0.76, blue: 0.96)
        case .desktop: return Color(red: 0.72, green: 0.65, blue: 0.85)
        case .messaging: return Color(red: 0.52, green: 0.79, blue: 0.77)
        case .media: return Color(red: 0.89, green: 0.77, blue: 0.47)
        default: return Color(red: 0.69, green: 0.77, blue: 0.93)
        }
    }
}
let ink = Color(red: 0.89, green: 0.90, blue: 0.86)
let muted = Color(red: 0.51, green: 0.55, blue: 0.52)
let surface = Color(red: 0.075, green: 0.09, blue: 0.083)
let accent = Color(red: 0.75, green: 0.88, blue: 0.58)

struct CapsuleButton: View {
    let title: String
    var symbol: String? = nil
    var primary = false
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14).frame(height: 34)
            .foregroundStyle(primary ? Color.black : ink)
            .background(primary ? accent : Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(primary ? 0 : 0.09)))
        }.buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.4 : 1)
    }
}

struct BoardView: View {
    @ObservedObject var manager: WindowManager
    @State private var showSettings = false
    @State private var search = ""
    @State private var showSaveLayout = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 200)
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
            VStack(spacing: 0) {
                header
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 21) {
                            Color.clear.frame(height: 0).id("tour-top")
                            if !manager.trusted { permissionBanner.tourSpot(.permission) }
                            gridSection.tourSpot(.grid)
                            CategoryBoard(manager: manager).tourSpot(.windows).id("tour-windows")
                        }.padding(26)
                    }
                    // The tour scrolls the part it explains into view.
                    .onChange(of: manager.tourStep) { _, index in
                        guard let index, manager.tourSteps.indices.contains(index) else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scroll.scrollTo(manager.tourSteps[index].spot == .windows ? "tour-windows" : "tour-top", anchor: .top)
                        }
                    }
                }
                footer
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(surface).foregroundStyle(ink)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSaveLayout) { SaveLayoutView(manager: manager) }
        .sheet(isPresented: $showSettings) { SettingsView(manager: manager) }
        .sheet(item: $manager.renameTarget) { lane in NewCategoryView(manager: manager, renameLane: lane) }
        .sheet(isPresented: Binding(get: { manager.renameWindowID != nil }, set: { if !$0 { manager.renameWindowID = nil } })) { RenameWindowView(manager: manager) }
        .sheet(isPresented: $manager.showAccessHelp) { AccessHelpView(manager: manager) }
        .overlayPreferenceValue(TourAnchors.self) { anchors in TourOverlay(manager: manager, anchors: anchors) }
        .onAppear { if !manager.settings.hasSeenTour && manager.tourStep == nil { manager.startTour() } }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(accent).frame(width: 34, height: 34)
                    Image(systemName: "rectangle.split.3x1.fill").font(.system(size: 18)).foregroundStyle(surface)
                }
                Text("lanes").font(.system(size: 27, weight: .semibold, design: .rounded)).tracking(-1)
            }.padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 32)
            Text("YOUR WORKSPACE").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(muted).padding(.horizontal, 22).padding(.bottom, 14)
            ScrollView { VStack(spacing: 0) {
            ForEach(Array(manager.enabledLanes.enumerated()), id: \.element.id) { index, lane in
                Button {
                    manager.selectGridCategory(lane); search = ""
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: lane.symbol).font(.system(size: 14)).foregroundStyle(lane.color).frame(width: 18)
                        Text(manager.name(lane)).font(.system(size: 12, weight: manager.selectedLane == lane ? .semibold : .regular))
                        Spacer()
                        Text(manager.discoveryCount(lane)).font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                    }.padding(.horizontal, 12).frame(height: 40)
                    .background(manager.selectedLane == lane ? Color.white.opacity(0.06) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 3)
                .draggable("lane:" + lane.rawValue)
                .help(Lane.allCases.firstIndex(of: lane).map { "Cycle windows: Control–Option–Command–\($0 + 1)" } ?? "Focus a window here, then Control–Option–Command–Tab to cycle")
                .contextMenu { Button("Rename category…") { manager.renameTarget = lane }; Button("Delete category", role: .destructive) { manager.editGrid { manager.removeCategory(lane) } }.disabled(manager.enabledLanes.count <= 1) }
                .dropDestination(for: String.self) { values, _ in
                    guard values.contains(where: { $0.hasPrefix("lane:") }) else { return manager.receiveDrop(values, into: lane) }
                    var placed = false; manager.editGrid { placed = manager.receiveDrop(values, into: lane) }; return placed
                }
            }
            }}.frame(maxHeight: .infinity).tourSpot(.categories)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Circle().fill(manager.trusted ? accent : Color.orange).frame(width: 6, height: 6)
                    Text(manager.trusted ? "Window control ready" : "Window control needed").font(.system(size: 10)).foregroundStyle(muted)
                }
                Text("A little order.\nA lot more headspace.").font(.system(size: 16, weight: .medium)).lineSpacing(4).foregroundStyle(ink.opacity(0.72))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Open Lanes from any app").font(.system(size: 10)).foregroundStyle(muted)
                    Text("Control + Option + Command + Space").font(.system(size: 10, weight: .medium)).foregroundStyle(accent).fixedSize(horizontal: false, vertical: true)
                    Text("or click the Lanes icon in the menu bar").font(.system(size: 10)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                }.tourSpot(.openLanes)
            }.padding(20)
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            Button { showSettings = true } label: {
                HStack(spacing: 9) { Image(systemName: "slider.horizontal.3"); Text("Preferences").lineLimit(1); Spacer() }
                    .font(.system(size: 11)).padding(20)
            }.buttonStyle(.plain).keyboardShortcut(",", modifiers: .command).tourSpot(.preferences)
        }.background(Color.black.opacity(0.14))
    }
    var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Room to think.").font(.system(size: 24, weight: .medium)).tracking(-0.6)
                Text(manager.trusted ? "\(manager.windows.count) \(manager.windows.count == 1 ? "window" : "windows")  /  \(manager.enabledLanes.count) \(manager.enabledLanes.count == 1 ? "lane" : "lanes")  /  one clear desktop" : "\(manager.runningApps.count) running apps  /  window access needed").font(.system(size: 11)).foregroundStyle(muted)
            }
            Spacer()
            CapsuleButton(title: "Restore", symbol: "arrow.uturn.backward", disabled: !manager.canUndo) { manager.undo() }
                .help("Put every window back where it was before Lanes moved it. Quitting Lanes does the same.")
                .tourSpot(.restore)
            CapsuleButton(title: "Organize", symbol: "rectangle.3.group", primary: true, disabled: !manager.trusted || manager.busy) { manager.autoOrganize() }
                .tourSpot(.organize)
                .help("Organize open windows while keeping your edited grid. Use Auto layout to choose new sizes. Control–Option–Command–Return; Right Command twice by default.")
        }.padding(.horizontal, 26).padding(.vertical, 22)
    }
    func presetChip(_ title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) { Image(systemName: symbol); Text(title) }
                .font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(active ? accent : ink.opacity(0.8))
                .background(active ? accent.opacity(0.08) : Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(active ? accent.opacity(0.35) : Color.white.opacity(0.07)))
        }.buttonStyle(.plain)
    }
    var permissionBanner: some View {
        HStack(spacing: 13) {
            Image(systemName: "hand.raised").font(.system(size: 20)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Let Lanes arrange your windows").font(.system(size: 12, weight: .semibold))
                Text("Turn on Lanes in System Settings. Lanes reads window titles, moves and resizes windows, and brings the one you pick forward. Nothing leaves your Mac.").font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            CapsuleButton(title: "Open System Settings", primary: true) { manager.requestAccess() }
            Button("Help") { manager.showAccessHelp = true }.font(.system(size: 11))
        }.padding(16).background(accent.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(accent.opacity(0.18)))
    }
    var gridSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("THE GRID").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(muted)
                Spacer()
                Menu {
                    ForEach(manager.screens, id: \.self) { screen in
                        Button("\(screen.localizedName) · \(Int(screen.frame.width)) × \(Int(screen.frame.height))") {
                            manager.changeScreen(WindowManager.displayID(screen))
                        }
                    }
                } label: {
                    HStack(spacing: 5) { Image(systemName: "display"); Text(manager.displayLabel); Image(systemName: "chevron.down").font(.system(size: 8)) }
                        .font(.system(size: 10)).foregroundStyle(muted)
                }.menuStyle(.borderlessButton).fixedSize()
                    .help("Each display keeps its own grid. Lanes switches when you plug in or unplug a display.")
            }
            Text("PRESETS").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(muted)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(PresetShape.allCases) { shape in
                        presetChip(shape.title, symbol: shape.symbol, active: manager.presetPreview?.shape == shape) { manager.previewPreset(shape) }
                            .help(shape.subtitle + ". The main category is the one selected in the sidebar.")
                    }
                    if !manager.settings.savedLayouts.isEmpty { Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 22) }
                    ForEach(manager.settings.savedLayouts) { layout in
                        presetChip(layout.name, symbol: "square.grid.2x2", active: manager.presetPreview?.savedID == layout.id) { manager.previewSavedLayout(layout) }
                            .help("Your preset. Click to preview it.")
                            .contextMenu { Button("Delete preset", role: .destructive) { if manager.presetPreview?.savedID == layout.id { manager.presetPreview = nil }; manager.deleteSavedLayout(layout.id) } }
                    }
                    Button { showSaveLayout = true } label: { Label("Save as preset…", systemImage: "plus") }.font(.system(size: 11))
                        .help("Save the current grid, its categories and windows shown at once as your own preset")
                }
            }.scrollIndicators(.hidden)
            if let preview = manager.presetPreview {
                HStack(spacing: 10) {
                    Image(systemName: "eye").foregroundStyle(accent)
                    Text("Previewing \(preview.name). Nothing on your screen has changed.").font(.system(size: 11))
                    Spacer()
                    Button("Cancel") { manager.presetPreview = nil }.font(.system(size: 11)).keyboardShortcut(.cancelAction)
                    Button { manager.applyPresetPreview() } label: {
                        Text("Apply").font(.system(size: 11, weight: .semibold)).foregroundStyle(surface).padding(.horizontal, 14).padding(.vertical, 6).background(accent).clipShape(Capsule())
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 14).padding(.vertical, 10).background(accent.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.25)))
            }
            HStack(spacing: 8) {
                Button("Apply this grid") { manager.arrange() }.font(.system(size: 11)).disabled(!manager.trusted)
                Button("Auto layout") { manager.autoOrganize(forceAutoLayout: true) }.font(.system(size: 11)).disabled(!manager.trusted || manager.busy).help("Choose new category sizes for the current workload")
                Button("Back to previous layout") { manager.restorePreviousLayout() }
                    .font(.system(size: 11)).disabled(manager.settings.previousLayout == nil)
                Spacer()
                Button { manager.onSwitcher?() } label: { Image(systemName: "rectangle.bottomthird.inset.filled").foregroundStyle(muted) }.buttonStyle(.plain).help("Show the floating lane switcher")
                Button { manager.showGrid() } label: { Image(systemName: "viewfinder").foregroundStyle(muted) }.buttonStyle(.plain).help("Show the lane boundaries on your display")
            }
            if manager.gridDraft != nil {
                HStack(spacing: 10) {
                    Image(systemName: "pencil").foregroundStyle(accent)
                    Text("You changed the grid. Nothing on your screen has changed yet.").font(.system(size: 11))
                    Spacer()
                    Button("Discard") { manager.discardGridDraft() }.font(.system(size: 11))
                    Button { manager.applyGridDraft() } label: {
                        Text("Apply").font(.system(size: 11, weight: .semibold)).foregroundStyle(surface).padding(.horizontal, 14).padding(.vertical, 6).background(accent).clipShape(Capsule())
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 14).padding(.vertical, 10).background(accent.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.25)))
            }
            GridEditor(manager: manager)
            HStack {
                Text(manager.settings.doubleRightCommand ? "Right Command twice → Organize" : "Control + Option + Command + Return → Organize").font(.system(size: 10)).foregroundStyle(muted)
                Spacer()
                Text(manager.settings.useCustomGrid ? "Custom grid · Organize keeps your sizes" : "Automatic grid")
                    .font(.system(size: 10)).foregroundStyle(manager.selectedTemplateChanged ? accent : muted)
            }
        }
    }
    var filteredWindows: [ManagedWindow] {
        manager.items(manager.selectedLane).filter { search.isEmpty || (manager.windowLabel($0) + $0.title + $0.appName).localizedCaseInsensitiveContains(search) }
    }
    var windowSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: manager.selectedLane.symbol).foregroundStyle(manager.selectedLane.color)
                    Text(manager.name(manager.selectedLane)).font(.system(size: 16, weight: .medium))
                    Text(manager.discoveryCount(manager.selectedLane)).font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(Color.white.opacity(0.05)).clipShape(Capsule())
                }
                Spacer()
                HStack(spacing: 5) {
                    Text("Windows shown at once").font(.system(size: 10)).foregroundStyle(muted)
                    Picker("Windows shown at once", selection: Binding(get: { manager.grid.capacity(manager.selectedLane) }, set: { value in manager.editGrid { manager.setCapacity(manager.selectedLane, value) } })) {
                        ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                    }.labelsHidden().frame(width: 52)
                }
                if manager.selectedLane == .browser {
                    Button("Side by side") { manager.editGrid { manager.setCapacity(.browser, 2) } }
                        .font(.system(size: 10)).disabled(manager.grid.capacity(.browser) == 2)
                        .help("Show two separate browser windows next to each other")
                }
                Button { manager.refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 12)).foregroundStyle(muted) }.buttonStyle(.plain).padding(.leading, 10).help("Refresh open windows")
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(muted)
                TextField(manager.trusted ? "Find a window in \(manager.name(manager.selectedLane).lowercased())…" : "Find an app in \(manager.name(manager.selectedLane).lowercased())…", text: $search).textFieldStyle(.plain).font(.system(size: 11))
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(muted) }.buttonStyle(.plain) }
            }.padding(10).background(Color.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 6))
            if !manager.trusted {
                appDiscovery
            } else if filteredWindows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: manager.selectedLane.symbol).font(.system(size: 25)).foregroundStyle(manager.selectedLane.color.opacity(0.4))
                    Text(manager.trusted ? (search.isEmpty ? "No windows in this lane yet" : "No matching windows") : "Your open windows will appear here").font(.system(size: 12, weight: .medium))
                    Text(manager.trusted ? "Open an app, refresh, or move a window here from another lane." : "Enable window control to discover and arrange them.").font(.system(size: 10)).foregroundStyle(muted)
                }.frame(maxWidth: .infinity).padding(.vertical, 23).background(Color.white.opacity(0.018)).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 1) {
                    ForEach(filteredWindows) { window in
                        WindowRow(manager: manager, window: window)
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Text(manager.selectedLane.hint).font(.system(size: 10)).foregroundStyle(muted)
                Spacer()
                if manager.trusted { pageControls } else { Text("Apps only · enable access for individual windows").font(.system(size: 10)).foregroundStyle(muted) }
            }
        }.simultaneousGesture(TapGesture().onEnded { manager.gridSelectionActive = false })
    }
    var appDiscovery: some View {
        let apps = manager.apps(manager.selectedLane).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "lock.open").foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Running apps are visible; window access is not recognized").font(.system(size: 12, weight: .medium))
                    Text("Enable Lanes in the macOS permission panel to see window titles and organize them.")
                        .font(.system(size: 10)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                CapsuleButton(title: "Enable window control", primary: true) { manager.requestAccess() }
            Button("Access help") { manager.showAccessHelp = true }.font(.system(size: 11))
            }.padding(14).background(accent.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 8))
            if apps.isEmpty {
                Text(search.isEmpty ? "No running apps assigned to this category. Try another category." : "No matching apps.")
                    .font(.system(size: 11)).foregroundStyle(muted).padding(.vertical, 14)
            } else {
                VStack(spacing: 1) {
                    ForEach(apps) { app in
                        HStack(spacing: 11) {
                            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 25, height: 25) }
                            Text(app.name).font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("RUNNING APP").font(.system(size: 8)).tracking(0.5).foregroundStyle(muted)
                            Button("Show app") { manager.activateApp(app) }.font(.system(size: 10))
                            Menu {
                                Section("Always send \(app.name) to") {
                                    ForEach(manager.enabledLanes) { lane in Button(manager.name(lane)) { manager.assignApp(app, to: lane) } }
                                }
                            } label: { Image(systemName: "ellipsis").foregroundStyle(muted) }.menuStyle(.borderlessButton).fixedSize()
                        }.padding(.horizontal, 12).padding(.vertical, 11).background(Color.white.opacity(0.035))
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    var pageControls: some View {
        HStack(spacing: 10) {
            Button { manager.cycle(manager.selectedLane, delta: -1) } label: { Image(systemName: "chevron.left").font(.system(size: 10)) }.buttonStyle(.plain).disabled(manager.items(manager.selectedLane).isEmpty)
            Text(manager.windowCounter(manager.selectedLane)).font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
            Button { manager.cycle(manager.selectedLane) } label: { Image(systemName: "chevron.right").font(.system(size: 10)) }.buttonStyle(.plain).disabled(manager.items(manager.selectedLane).isEmpty)
        }
    }
    var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: manager.canUndo ? "checkmark.circle" : "circle.dotted").foregroundStyle(accent)
            Text(manager.status).lineLimit(2).font(.system(size: 10)).foregroundStyle(muted)
            Spacer(minLength: 8)
            Text("LOCAL. QUIET. YOURS.").font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(muted.opacity(0.6))
        }.padding(.horizontal, 26).frame(minHeight: 44).background(Color.black.opacity(0.12))
    }
}

struct WindowRow: View {
    @ObservedObject var manager: WindowManager
    let window: ManagedWindow
    var visible: Bool { manager.visibleItems(window.lane).contains(where: { $0.id == window.id }) }
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(muted.opacity(0.5)).frame(width: 9)
            if let icon = window.icon { Image(nsImage: icon).resizable().frame(width: 25, height: 25) }
            VStack(alignment: .leading, spacing: 3) {
                Text(manager.windowLabel(window)).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text(window.appName).font(.system(size: 9)).foregroundStyle(muted)
            }
            Spacer()
            Text(visible ? "VISIBLE" : "STACKED").font(.system(size: 8, weight: .medium)).tracking(0.6)
                .foregroundStyle(visible ? window.lane.color : muted).padding(.horizontal, 7).padding(.vertical, 4)
                .background((visible ? window.lane.color : muted).opacity(0.07)).clipShape(Capsule())
            Menu {
                Section("Move this window to") {
                    ForEach(manager.enabledLanes) { lane in Button(manager.name(lane)) { manager.assign(window, to: lane) } }
                }
                Section("Always send \(window.appName) to") {
                    ForEach(manager.enabledLanes) { lane in Button(manager.name(lane)) { manager.assign(window, to: lane, rememberApp: true) } }
                }
                Button("Show window") { manager.reveal(window) }
                Button("Rename tab…") { manager.beginRenamingWindow(window) }
            } label: { Image(systemName: "ellipsis").foregroundStyle(muted).frame(width: 20, height: 25) }.menuStyle(.borderlessButton).fixedSize()
        }.padding(.horizontal, 12).padding(.vertical, 10).background(Color.white.opacity(0.035))
            .contentShape(Rectangle()).onTapGesture(count: 2) { manager.reveal(window) }
            .draggable(window.id)
            .dropDestination(for: String.self) { values, _ in return manager.reorderTab(values, before: window) }
            .help("Double-click to show. Drag to another lane or use the menu to reassign.")
    }
}

struct RenameWindowView: View {
    @ObservedObject var manager: WindowManager
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename window tab").font(.system(size: 22, weight: .medium))
            Text("Choose a name such as Server, Build, or Research. This changes its label in Lanes.").font(.system(size: 12)).foregroundStyle(muted)
            TextField("Window name", text: $label).textFieldStyle(.roundedBorder).focused($focused).onSubmit { rename() }
            HStack {
                Button("Use original title") { label = ""; rename() }
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { rename() }.keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 450).background(surface).foregroundStyle(ink).preferredColorScheme(.dark)
            .onAppear { if let id = manager.renameWindowID, let window = manager.windows.first(where: { $0.id == id }) { label = manager.windowLabel(window) }; focused = true }
    }
    func rename() { if let id = manager.renameWindowID { manager.renameWindow(id, name: label) }; dismiss() }
}

struct SettingsView: View {
    @ObservedObject var manager: WindowManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Make it your space.").font(.system(size: 23, weight: .medium)); Spacer(); Button("Done") { manager.save(); dismiss() }.keyboardShortcut(.defaultAction) }
            Text("Windows stay open in their category. Extra windows stack behind the selected ones; sifting brings the next window forward. Restore returns the original desktop.")
                .font(.system(size: 12)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text("New windows").font(.system(size: 12))
                Picker("New windows", selection: Binding(get: { manager.settings.newWindowPlacement }, set: { manager.settings.newWindowPlacement = $0; manager.save(); manager.updateNewWindowWatch() })) {
                    ForEach(NewWindowPlacement.allCases) { choice in Text(choice.title).tag(choice) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 260)
            }
            Text(manager.settings.newWindowPlacement == .center ? "A new window opens centered on this display at its own size. Nothing else moves. New tabs stay with their window."
                 : manager.settings.newWindowPlacement == .leave ? "New windows stay wherever their app opens them. Nothing moves until you press Organize."
                 : "After Organize, each new window goes into its category. Existing windows stay fixed. Auto layout explicitly chooses new category sizes.")
                .font(.system(size: 10)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            Toggle("Only collect windows from the selected display", isOn: Binding(get: { manager.settings.onlyTargetScreen }, set: { manager.settings.onlyTargetScreen = $0; manager.save(); manager.refresh() })).font(.system(size: 12))
            Toggle("Open Lanes at login", isOn: Binding(get: { manager.opensAtLogin }, set: { manager.setOpensAtLogin($0) })).font(.system(size: 12))
            Toggle("Short tab names", isOn: Binding(get: { manager.settings.shortTabNames }, set: { manager.settings.shortTabNames = $0; manager.save(); manager.onLaneControls?() })).font(.system(size: 12))
            Text("Messaging apps show their app name. Other windows show the first meaningful part of their title. Hover a tab for the full title, or rename it to choose your own.")
                .font(.system(size: 10)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            Toggle("Show a window strip for each category", isOn: Binding(get: { manager.settings.showLaneControls }, set: { manager.settings.showLaneControls = $0; manager.save(); manager.selectedTemplateChanged = true; if !$0 { manager.onHideLaneControls?() } })).font(.system(size: 12))
            HStack {
                Text("Strip position").font(.system(size: 12))
                Picker("Strip position", selection: Binding(get: { manager.settings.stripPlacement }, set: { manager.setStripPlacement($0) })) {
                    ForEach(StripPlacement.allCases) { placement in Text(placement.title).tag(placement) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 260)
                Button("Reset positions") { manager.resetStripPosition() }.font(.system(size: 11))
                    .disabled(manager.settings.stripPlacement != .onWindows || manager.settings.stripPositions.isEmpty)
            }.disabled(!manager.settings.showLaneControls)
            Text(manager.settings.stripPlacement == .onWindows
                 ? "Strips sit centered on the top edge of each category, with no padding. Drag a strip's ≡ handle to put it anywhere; Lanes remembers the spot."
                 : "Lanes keeps a band above each category for its strip. Windows start below the band.")
                .font(.system(size: 10)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Window strip style").font(.system(size: 12))
                Picker("Window strip style", selection: Binding(get: { manager.settings.windowStripStyle }, set: { manager.settings.windowStripStyle = $0; manager.stripAppearanceChanged() })) {
                    ForEach(WindowStripStyle.allCases) { style in Text(style.title).tag(style) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 340)
            }.disabled(!manager.settings.showLaneControls)
            HStack {
                Text("Strip size").font(.system(size: 12))
                Slider(value: Binding(get: { manager.settings.windowStripScale }, set: { manager.settings.windowStripScale = $0; manager.stripAppearanceChanged(retile: false) }), in: 0.8...1.5, step: 0.1, onEditingChanged: { editing in if !editing { manager.stripAppearanceChanged() } }).frame(width: 160)
                Text("\(Int(manager.settings.windowStripScale * 100))% ").font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
            }.disabled(!manager.settings.showLaneControls)
            Text("Bars fade completely transparent when idle. Hover their area to reveal them; scroll or use Left/Right and 1–9 (0 = window 10). Right-click to customize.")
                .font(.system(size: 10)).foregroundStyle(muted)
            Toggle("Reserve a shelf for mini players", isOn: Binding(get: { manager.gridLanes.contains(.media) }, set: { on in manager.editGrid { if on { manager.restoreCategory(.media) } else { manager.removeCategory(.media) } } })).font(.system(size: 12))
            Text("Use a Picture-in-Picture or compact player window, then send it to category 6. App minimum sizes still apply.").font(.system(size: 10)).foregroundStyle(muted)
            HStack {
                Text("Space between windows").font(.system(size: 12))
                Slider(value: Binding(get: { manager.settings.gap }, set: { manager.settings.gap = $0; manager.selectedTemplateChanged = true; manager.save() }), in: 4...28, step: 2).frame(width: 160)
                Text("\(Int(manager.settings.gap)) pt").font(.system(size: 11, design: .monospaced)).foregroundStyle(accent).frame(width: 40)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("Windows shown at once").font(.system(size: 12, weight: .medium))
                ForEach(manager.enabledLanes) { lane in
                    HStack {
                        Image(systemName: lane.symbol).foregroundStyle(lane.color).frame(width: 20)
                        Text(manager.name(lane)).font(.system(size: 11)); Spacer()
                        Picker(manager.name(lane), selection: Binding(get: { manager.grid.capacity(lane) }, set: { value in manager.editGrid { manager.setCapacity(lane, value) } })) { ForEach(1...4, id: \.self) { Text("\($0)").tag($0) } }.labelsHidden().frame(width: 64)
                    }
                }
            }
            Divider()
            Toggle("Double-tap Right Command to organize", isOn: Binding(get: { manager.settings.doubleRightCommand }, set: { manager.settings.doubleRightCommand = $0; manager.save() })).font(.system(size: 12))
            Text("Two quick taps, with no other keys held. Window control must be enabled for use in other apps.").font(.system(size: 10)).foregroundStyle(muted)
            Text("GLOBAL SHORTCUTS").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(muted)
            Text("Hold Control, Option and Command (the three keys left of the Space bar), then press:").font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                shortcut("Open Lanes", "Space")
                shortcut("Organize desktop", "Return")
                shortcut("Next window in categories 1–7", "1 to 7")
                shortcut("Cycle focused window’s category", "Tab")
                shortcut("Previous window in category", "Shift + Tab")
                shortcut("Send focused window to category", "Shift + 1 to 7")
                shortcut("Move focused window by 24 pt", "Arrow keys")
                shortcut("Resize focused window by 24 pt", "Shift + Arrow keys")
                shortcut("Restore window positions", "Z")
            }
            Text("ON A STRIP OR IN THE GRID").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(muted)
            VStack(spacing: 8) {
                shortcut("Switch windows in the hovered category", "Scroll, Left/Right arrow, 1 to 9, 0")
                shortcut("Delete the selected grid category", "Backspace")
            }
            if !manager.settings.hiddenLanes.isEmpty {
                Text("REMOVED CATEGORIES").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(muted)
                ForEach(manager.availableLanes.filter { manager.settings.hiddenLanes.contains($0.rawValue) }) { lane in
                    HStack {
                        Label(manager.name(lane), systemImage: lane.symbol).font(.system(size: 11)).foregroundStyle(lane.color)
                        Spacer()
                        Button("Restore") { manager.editGrid { manager.restoreCategory(lane) } }.font(.system(size: 11))
                    }
                }
            }
            Button("Reset category positions") { manager.resetPlacements() }.font(.system(size: 11))
            HStack {
                Button("Reset app assignments") { manager.resetRules() }.font(.system(size: 11))
                Spacer()
                Text("\(manager.settings.appRules.count) saved app rules").font(.system(size: 10)).foregroundStyle(muted)
            }
        }.padding(28)
        }.frame(width: 540, height: 730).background(surface).foregroundStyle(ink).preferredColorScheme(.dark)
    }
    func shortcut(_ label: String, _ keys: String) -> some View {
        HStack { Text(label).font(.system(size: 11)); Spacer(); Text(keys).font(.system(size: 11, design: .monospaced)).foregroundStyle(accent) }
    }
}

struct AccessHelpView: View {
    @ObservedObject var manager: WindowManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Turn on window control").font(.system(size: 22, weight: .medium)); Spacer(); Button("Done") { dismiss() } }
            Text("Lanes moves other apps' windows, so macOS asks you to allow it once. Lanes uses this only to read window titles, move and resize windows, and bring the window you pick forward. It makes no network requests.")
                .font(.system(size: 12)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            Text("1. Click Open System Settings.\n2. In the list that opens, switch Lanes on. macOS may ask for your password.\n3. Come back here. Lanes notices within a few seconds.").font(.system(size: 12)).lineSpacing(7)
            Text("Already switched on but still not working? This happens after replacing Lanes with a newer download. Select Lanes in that list, remove it with the minus button, add it again with the plus button, and switch it on.")
                .font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            Text("This copy: \(Bundle.main.bundlePath)").font(.system(size: 11, design: .monospaced)).foregroundStyle(accent).textSelection(.enabled)
            HStack {
                Button("Open System Settings") { manager.requestAccess() }
                Button("Show Lanes in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
            }.font(.system(size: 11))
            HStack {
                Image(systemName: manager.trusted ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(manager.trusted ? accent : .orange)
                Text(manager.trusted ? "Window control is on" : "Window control is not on yet").font(.system(size: 11))
                Spacer()
                Button("Recheck access") { manager.refresh(); if manager.trusted { dismiss() } }.font(.system(size: 11))
            }
        }.padding(28).frame(width: 590).background(surface).preferredColorScheme(.dark)
    }
}

struct SaveLayoutView: View {
    @ObservedObject var manager: WindowManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save as preset").font(.system(size: 22, weight: .medium))
            Text("Save these category positions, sizes, and how many windows each shows. Your layouts stay available alongside the built-in presets.")
                .font(.system(size: 12)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            TextField("Layout name", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { if manager.saveGridLayout(name: name) { dismiss() } }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 450).background(surface).foregroundStyle(ink).preferredColorScheme(.dark)
    }
}
