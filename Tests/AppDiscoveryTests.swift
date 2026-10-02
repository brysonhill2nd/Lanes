import AppKit
import ApplicationServices

@main struct AppDiscoveryTests {
    @MainActor static func main() {
        let manager = WindowManager(startPolling: false)
        let trusted = AXIsProcessTrusted()
        let expected = Set(NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier > 0 && $0.processIdentifier != getpid() && !$0.isTerminated
        }.map(\.processIdentifier))
        manager.refreshRunningApps()
        let found = Set(manager.runningApps.map(\.pid))
        precondition(found == expected, "all running desktop apps must be discoverable through NSWorkspace")
        precondition(manager.runningApps.allSatisfy { manager.availableLanes.contains($0.lane) }, "apps keep their own category, even a shelved one, instead of being counted in another")
        let actualWindows = manager.windows
        manager.trusted = false
        for lane in manager.enabledLanes {
            precondition(manager.discoveryCount(lane) == "\(manager.apps(lane).count) apps", "counts must identify apps, not claim window discovery")
        }
        precondition(manager.windows.count == actualWindows.count, "app discovery must not fabricate window entries")
        precondition(manager.runningApps.count == found.count, "discovery list cannot contain duplicate processes")
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("lanes-category-test-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let file = fixture.appendingPathComponent("settings.json")
        let categories = WindowManager(settingsFile: file, startPolling: false)
        precondition(categories.addCategory(name: "Research"), "a custom category must fit into a populated grid")
        let research = categories.selectedLane
        precondition(research.isCustom && categories.name(research) == "Research")
        precondition(GridGeometry.valid(categories.layoutRects(), lanes: categories.enabledLanes))
        precondition(categories.addCategory(name: "Music"), "multiple custom categories must be allowed")
        categories.renameCategory(research, name: "Reading")
        let reload = WindowManager(settingsFile: file, startPolling: false)
        precondition(reload.name(research) == "Reading" && reload.enabledLanes.contains(research), "custom categories and renames must survive relaunch")
        var focusReleased = false
        reload.onGridSelection = { focusReleased = true }
        reload.selectGridCategory(research)
        precondition(focusReleased && reload.gridSelectionActive, "selecting a grid section must release text-field focus for Backspace")
        reload.deleteSelectedCategory()
        precondition(!reload.enabledLanes.contains(research) && reload.availableLanes.contains(research), "Backspace deletion must be reversible")
        reload.restoreCategory(research)
        precondition(reload.enabledLanes.contains(research) && reload.name(research) == "Reading")
        precondition(GridGeometry.valid(reload.layoutRects(), lanes: reload.enabledLanes), "restore cannot overlap existing categories")
        precondition(!reload.addCategory(name: "   "), "empty names cannot create categories")
        reload.settings.appRules["org.example.reader"] = research.rawValue
        reload.save()
        let original = reload.editorRect(research)
        precondition(reload.receiveShelfDrop(["lane:" + research.rawValue]), "workspace category drags must move it to the shelf")
        precondition(reload.settings.appRules["org.example.reader"] == research.rawValue, "shelving must preserve app assignments")
        precondition(!reload.enabledLanes.contains(research) && reload.settings.shelvedLanes.contains(research.rawValue))
        precondition(!reload.receiveShelfDrop(["unrelated window"]), "window and unrelated drops cannot delete a category")
        let shelfReload = WindowManager(settingsFile: file, startPolling: false)
        shelfReload.settings.hiddenLanes.removeAll { $0 == research.rawValue }
        precondition(!shelfReload.enabledLanes.contains(research), "auto-sort clearing empty-category state must not unshelve a removed group")
        precondition(!shelfReload.receiveWorkspaceDrop(["lane:" + research.rawValue], at: CGPoint(x: -1, y: 2), in: CGSize(width: 1000, height: 500)))
        precondition(shelfReload.receiveWorkspaceDrop(["lane:" + research.rawValue], at: CGPoint(x: original.midX * 1000, y: original.midY * 500), in: CGSize(width: 1000, height: 500)))
        precondition(shelfReload.editorRect(research) == original, "dropping into the freed region must put the category back there")
        precondition(shelfReload.settings.appRules["org.example.reader"] == research.rawValue && !shelfReload.settings.shelvedLanes.contains(research.rawValue))
        precondition(shelfReload.receiveShelfDrop(["lane:" + research.rawValue]))
        let target = shelfReload.editorRect(.terminal)
        let targetPoint = CGPoint(x: target.minX + target.width * 0.75, y: target.midY)
        precondition(shelfReload.receiveWorkspaceDrop(["lane:" + research.rawValue], at: CGPoint(x: targetPoint.x * 1000, y: targetPoint.y * 500), in: CGSize(width: 1000, height: 500)))
        precondition(shelfReload.editorRect(research).contains(targetPoint), "drop on an occupied region must split that region at the requested location")
        precondition(GridGeometry.valid(shelfReload.layoutRects(), lanes: shelfReload.enabledLanes))
        for lane in shelfReload.enabledLanes.dropFirst() { precondition(shelfReload.receiveShelfDrop(["lane:" + lane.rawValue])) }
        precondition(!shelfReload.receiveShelfDrop(["lane:" + shelfReload.enabledLanes[0].rawValue]), "drag removal must protect the final category")
        let terminalWindows = (0..<4).map { index in
            ManagedWindow(id: "terminal-test-\(index)", element: AXUIElementCreateApplication(getpid()), pid: getpid(), bundleID: "com.apple.Terminal", appName: "Terminal", title: "Shell \(index)", icon: nil, frame: CGRect(x: 0, y: 0, width: 1000, height: 900), minimized: false, lane: .terminal)
        }
        let tabManager = WindowManager(settingsFile: fixture.appendingPathComponent("tabs.json"), startPolling: false)
        tabManager.windows = terminalWindows
        tabManager.visibleSlotIDs[.terminal] = Array(terminalWindows.prefix(2).map(\.id))
        precondition(tabManager.reorderTab(["tab:" + terminalWindows[3].id], before: terminalWindows[0]))
        precondition(tabManager.items(.terminal).map(\.id) == ["terminal-test-3", "terminal-test-0", "terminal-test-1", "terminal-test-2"])
        precondition(tabManager.visibleItems(.terminal).map(\.id) == ["terminal-test-0", "terminal-test-1"], "drag reordering tabs must not switch either visible terminal")
        tabManager.renameWindow(terminalWindows[0].id, name: " Server ")
        let reloadedTabs = WindowManager(settingsFile: fixture.appendingPathComponent("tabs.json"), startPolling: false)
        precondition(reloadedTabs.windowLabel(terminalWindows[0]) == "Server", "renamed terminal labels survive app restart while that window stays open")
        precondition(reloadedTabs.settings.windowOrder["terminal"]?.first == "terminal-test-3", "tab ordering survives restart for open windows")
        let terminalRect = tabManager.editorRect(.terminal)
        tabManager.editCategory(.terminal, rect: CGRect(x: terminalRect.minX, y: terminalRect.minY, width: terminalRect.width * 0.9, height: terminalRect.height * 0.9))
        precondition(tabManager.settings.useCustomGrid, "manual width and height edits must change Organize to preserve the grid")
        tabManager.hoveredLane = .terminal
        tabManager.targetSlot(.terminal, index: 1)
        precondition(tabManager.activeSlot[.terminal] == 1 && tabManager.activeWindow(.terminal)?.id == "terminal-test-1", "hover targets the bottom pane without changing either window")
        precondition(tabManager.visibleItems(.terminal).map(\.id) == ["terminal-test-0", "terminal-test-1"])
        tabManager.trusted = false // Fixture AX elements must never manipulate actual windows.
        precondition(tabManager.saveGridLayout(name: "My work"))
        let savedWork = tabManager.settings.savedLayouts.last!
        let workRects = tabManager.layoutRects()
        tabManager.previewPreset(.focus)
        precondition(tabManager.presetPreview != nil && tabManager.layoutRects() == workRects, "previewing a preset changes nothing until Apply")
        tabManager.presetPreview = nil
        precondition(tabManager.layoutRects() == workRects, "Cancel leaves the grid exactly as it was")
        tabManager.previewPreset(.focus); tabManager.applyPresetPreview()
        precondition(tabManager.layoutRects() != workRects && tabManager.settings.previousLayout?.rects == workRects, "applying a preset keeps the grid you had as the previous layout")
        precondition(!tabManager.layoutRects().isEmpty, "applying a preset never leaves the grid empty")
        tabManager.restorePreviousLayout()
        precondition(tabManager.layoutRects() == workRects, "Back restores exact prior sizes")
        tabManager.setCapacity(.terminal, 1)
        tabManager.loadGridLayout(savedWork)
        precondition(tabManager.settings.capacity(.terminal) == 2 && tabManager.layoutRects() == workRects, "saved presets restore geometry and simultaneous windows")
        precondition(tabManager.saveGridLayout(name: "My work"))
        precondition(tabManager.settings.savedLayouts.last!.name == "My work 2", "duplicate names never overwrite an earlier preset")
        let presetsReload = WindowManager(settingsFile: fixture.appendingPathComponent("tabs.json"), startPolling: false)
        precondition(presetsReload.settings.savedLayouts.count == 2 && presetsReload.settings.previousLayout != nil, "named presets and prior grid survive restart")
        let unsplit = tabManager.layoutRects()
        let splitWindowID = tabManager.visibleItems(.terminal).dropFirst().first!.id
        let split = tabManager.splitCategory(.terminal, sideBySide: true)!
        precondition(GridGeometry.valid(tabManager.layoutRects(), lanes: tabManager.enabledLanes), "split creates two valid independent regions")
        precondition(tabManager.items(split).map(\.id) == [splitWindowID] && tabManager.settings.capacity(.terminal) == 1)
        precondition(tabManager.settings.windowCategories[splitWindowID] == split.rawValue, "each split window keeps its own category across restart")
        let untouched = tabManager.editorRect(split)
        tabManager.moveWindow(terminalWindows[2], to: split)
        precondition(tabManager.items(split).count == 2 && tabManager.editorRect(split) == untouched, "adding another app window only changes that region's queue")
        tabManager.saveGridLayout(name: "Split work")
        let savedSplit = tabManager.settings.savedLayouts.last!
        tabManager.undoLayout()
        precondition(tabManager.layoutRects() == unsplit && !tabManager.availableLanes.contains(split), "Undo split restores the prior category grid")
        tabManager.loadGridLayout(savedSplit)
        precondition(tabManager.enabledLanes.contains(split) && tabManager.items(split).count == 2, "saved split layouts recreate categories and their window assignments after Undo")
        let countManager = WindowManager(settingsFile: fixture.appendingPathComponent("counts.json"), startPolling: false)
        countManager.trusted = false
        countManager.windows = terminalWindows
        countManager.visibleSlotIDs[.terminal] = Array(terminalWindows.prefix(2).map(\.id))
        countManager.activeSlot[.terminal] = 1
        let unchangedGrid = countManager.layoutRects(), peerCapacity = countManager.settings.capacity(.messaging)
        countManager.setCapacity(.terminal, 1)
        precondition(countManager.visibleItems(.terminal).map(\.id) == [terminalWindows[1].id], "reducing two panes to one retains the selected bottom window")
        precondition(countManager.activeSlot[.terminal] == 0, "reducing the count retains a valid target pane")
        countManager.setCapacity(.terminal, 4)
        precondition(countManager.visibleItems(.terminal).count == 4 && countManager.activeWindow(.terminal)?.id == terminalWindows[1].id, "increasing the count fills additional panes without replacing the selected window")
        precondition(countManager.layoutRects() == unchangedGrid && countManager.settings.capacity(.messaging) == peerCapacity, "window counts change only the selected region's interior")
        let countReload = WindowManager(settingsFile: fixture.appendingPathComponent("counts.json"), startPolling: false)
        precondition(countReload.settings.capacity(.terminal) == 4, "each region's window count survives restart")
        var hoverChanges = 0
        reload.onHoveredLaneChanged = { hoverChanges += 1 }
        reload.hoveredLane = research; reload.hoveredLane = research; reload.hoveredLane = nil
        precondition(hoverChanges == 2, "hover key registration should only change on entering or leaving a lane")
        // Grid edits in the Lanes window stay a draft until Apply.
        let draftFile = fixture.appendingPathComponent("draft.json")
        let drafts = WindowManager(settingsFile: draftFile, startPolling: false)
        drafts.trusted = false // Fixture windows must never touch real ones.
        drafts.save()
        let savedBefore = try! Data(contentsOf: draftFile)
        let lanesBefore = drafts.enabledLanes, a = lanesBefore[0], b = lanesBefore[1]
        let rectA = drafts.settings.unitRect(for: a), rectB = drafts.settings.unitRect(for: b)
        drafts.editGrid { drafts.swapCategories(a, b) }
        precondition(drafts.gridDraft != nil && drafts.grid.unitRect(for: a) == rectB, "a grid edit shows in the Lanes window as a draft")
        precondition(drafts.settings.unitRect(for: a) == rectA && drafts.enabledLanes == lanesBefore, "the screen keeps the applied grid until Apply")
        precondition((try! Data(contentsOf: draftFile)) == savedBefore, "a draft is never saved over your settings")
        drafts.discardGridDraft()
        precondition(drafts.gridDraft == nil && drafts.grid.unitRect(for: a) == rectA, "Discard leaves everything as it was")
        drafts.editGrid { drafts.removeCategory(b) }
        precondition(drafts.enabledLanes.contains(b) && !drafts.gridLanes.contains(b), "removing a category waits for Apply")
        drafts.editGrid { drafts.restoreCategory(b) }
        drafts.editGrid { drafts.swapCategories(a, b) }
        drafts.editGrid { drafts.swapCategories(a, b) }
        drafts.applyGridDraft()
        precondition(drafts.gridDraft == nil && drafts.enabledLanes.contains(b), "Apply makes the draft the real grid")
        drafts.editGrid { drafts.swapCategories(a, b) }
        drafts.editGrid { drafts.swapCategories(a, b) }
        precondition(drafts.gridDraft == nil, "editing back to the applied grid clears the draft")
        drafts.settings.stripPositions[a.rawValue] = StripPosition(x: 0.2, y: 0.01)
        drafts.editGrid { drafts.swapCategories(a, b) }
        drafts.applyGridDraft()
        precondition(drafts.settings.stripPositions[a.rawValue] == nil, "a dragged strip goes back to the middle when its category's box changes")
        precondition(drafts.settings.unitRect(for: a) == rectB && (try! Data(contentsOf: draftFile)) != savedBefore, "Apply saves the new grid")
        print("PASS: grid edits stay a draft until Apply")
        print("PASS: running-app discovery, named categories, shelf drag removal/restore, preserved assignments, drop placement, last-category protection, and hover state")
        print("Live discovery: \(manager.runningApps.count) running apps; window control granted: \(trusted)")
    }
}
