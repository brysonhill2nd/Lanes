# Lanes

A native macOS menu bar organizer for an ultrawide desktop. Organize discovers your open windows, groups them by category, and chooses a readable grid for the current workload. Each category has a stack of individual windows, including separate Arc windows. Browser is a separate category for Arc, Safari, Chrome and other browsers; Previews is for video and document preview apps.

## Install

Lanes is free. It needs macOS 14 or later and runs on Apple Silicon and Intel Macs.

1. Download `Lanes-1.0.0.dmg` from [Releases](https://github.com/brysonhill2nd/Lanes/releases/latest), open it, and drag **Lanes** into **Applications**.
2. Open Lanes. Its icon appears in the menu bar and the Lanes window opens.
3. Click **Open System Settings** and switch Lanes on. macOS asks once, because Lanes moves other apps' windows. Lanes notices within a few seconds.
4. Click **Organize**, or tap **Right Command twice**.

Lanes starts with Browser filling the grid and every other category (Terminal, Messaging, Previews, Desktop, Simulators, Mini players) on the category shelf below it. Drag the ones you use up into the grid, size them, and press Apply; nothing on your screen changes before that. Video apps (Final Cut Pro, Premiere Pro, After Effects, DaVinci Resolve, CapCut, iMovie, Motion) go in Previews. Strips expand on hover, tab names are shortened, and new windows open in the center. Simulators, Previews, Desktop and Mini players wait on the category shelf; drag one into the grid to use it. Everything can be changed in the Lanes window and Preferences.

**Each display keeps its own grid.** On a laptop-shaped screen (narrower than 2:1) Lanes gives Browser 60% on the left and stacks up to two of your other categories (Terminal and Messaging first) on the right, one window each, with the rest on the shelf; a new install starts with Browser alone. Unplug an ultrawide and Lanes switches to the laptop grid; plug it back in and the ultrawide grid returns exactly as you left it. Changes you make on each display stay with that display. Switching displays changes the grid and strips only; press Organize to arrange your windows.

On first launch a short tour highlights each part of the Lanes window: Organize, Restore, the grid, categories, the window list, the strips on your screen, and Preferences. Take it again any time from the menu bar icon › **Take the tour**.

Lanes lives in the menu bar. To open it, click its menu bar icon, or hold Control, Option and Command (the three keys left of the Space bar) and press Space from any app. To keep it in the Dock as well, drag Lanes from your Applications folder into the Dock; clicking it there opens the Lanes window. To start Lanes automatically, turn on **Open Lanes at login** in Preferences.

### Privacy

Lanes makes no network requests and never records your screen. It has no accounts, analytics or update checks. It uses window control only to read window titles, move and resize windows, and bring the window you pick forward. Its settings live in `~/Library/Application Support/Lanes/settings.json`.

### Uninstall

1. Choose **Quit Lanes** from its menu bar icon. Quitting puts your windows back where they were.
2. Drag **Lanes** from Applications to the Trash.
3. Delete `~/Library/Application Support/Lanes`.
4. In System Settings, remove Lanes from **Privacy & Security › Accessibility**, and from **General › Login Items** if you turned on Open at login.

## Use

Open Lanes from Applications. A fresh launch gracefully replaces an older instance, restoring its managed windows first.

Click **Organize**, tap **Right Command twice**, or press **Control–Option–Command–Return** to place open windows. Until you edit the grid, Lanes can choose an automatic layout. After you resize, move or select a preset, Organize keeps those sizes and categories. **Auto layout** explicitly recalculates the grid for the current workload. Lanes gives larger regions to browsers and work apps and smaller regions to messaging and players. It remembers the exact window you were working in before opening Lanes, keeps it visible, and returns focus to it. Other categories retain their selected windows too. The active work category gets extra layout weight. It uses the selected display, reserves space for the category strips, and retries the layout with measured sizes if an app clamps its window dimensions. Empty categories stay on the category shelf. Categories you deliberately remove stay shelved until restored.

**Organize** and **Apply this grid** apply your manually edited layout. Inside Lanes, drag category centers to move them, edges to resize them, or use **Swap categories**. Shared borders resize neighboring regions together. The inspector accepts precise percentages; Snap to grid and Undo grid edit are available. **Grid edits are a draft.** Moving, resizing, swapping, splitting, adding or removing categories, and changing windows shown at once only change the grid in the Lanes window. A bar says nothing on your screen has changed yet; **Apply** arranges your windows into the new grid and **Discard** throws the changes away. Dropping a category on another one swaps them, and dropping it on free space fills that space.

**Categories**, at the bottom of the Lanes window, shows two sides: on the left, running apps or windows that have no category in your grid yet; on the right, every category in your grid with what is in it. Drag an app or window by its row onto a category; drag it back to the left side to undo. The small menu on each row does the same and lists only categories in your grid. Switch between **Apps** (remembered for every window of that app) and **Windows** (one specific window, so a single Arc window, a terminal, Spotify and ChatGPT can share a category). A window or app you drop on a category moves there right away, and Lanes never moves it out again just because of where it sits. To place a single browser or terminal tab, first make it its own window. Window choices last until that app quits.

**Presets** sit above the grid. Clicking one only previews it on the grid; nothing on your screen moves until you press **Apply**, and **Cancel** leaves everything as it was. The built-in presets arrange whatever categories you have, including Browser and your own: **Columns** puts every category side by side with busier ones wider, **Focus** puts the main category in the middle, and **Main + side** puts it on the left at 60%. The main category is the one selected in the sidebar.

The largest connected display is selected initially. The display selector changes it. Discovery includes standard windows and compact player windows on that display, including minimized windows and windows of hidden apps. Fullscreen windows and dialogs are excluded. Turn off display filtering in Preferences to collect windows from other displays.

## Sift through windows

After arranging, each category has a strip above its desktop windows. Preferences offers **Compact** (the default) and **Detailed**, plus a size slider. Bars fade all the way to transparent after 1.5 seconds idle, with a 0.3-second fade, and immediately reappear when hovered. Their transparent native tracking area stays in place. Window discovery and switching updates do not reveal all idle bars. Right-click a strip background to override its style for that category. Compact shows the category; Detailed includes names, icons, a counter and arrows. Smaller strips reserve less vertical space for app windows.

**Window strip style** (Preferences, or right-click a strip): **Compact** pills, **Detailed** (one wider pill with each window's name as a chip, as wide as its windows need), or **Expand on hover**, which rests compact and grows to the right into the detailed view while the mouse is on it (animated at the display's refresh rate), then shrinks a moment after it leaves. The category name and Top/Bottom chooser stay at the left edge in every style, so they never move under the mouse. Hovering never moves a window.

**Short tab names** (on by default) make strips readable without AI: messaging apps show their app name (two windows of one app add the conversation), and other windows show the first meaningful part of their title, without agent status symbols, unread counts, prices or user names, cut near 28 characters. Hover a tab for its full title; a name you type with Rename tab always wins. Strips keep 20 points clear of the display's sides.

A category with only one window has no strip, since there is nothing to switch to; the strip returns when a second window joins.

**Strip position** (Preferences) chooses where strips sit. **On the windows** (the default) centers each strip on the top edge of its category and gives windows the full height, with no padding. Drag a strip's ≡ handle to put it anywhere; Lanes remembers the spot per category, keeps it on screen, and moves it with the category when the grid is resized. Right-click a strip → **Move strip back to the top edge**, or use **Reset positions**. Strips on the windows fade to a faint outline instead of disappearing, so you never click an invisible strip. **Above the windows** keeps the previous reserved band.

- Hover a strip and **scroll** to cycle that category.
- While hovered, bare **Left/Right** cycles backward/forward; **1–9** selects tabs 1–9 and **0** selects tab 10. Numbers follow the saved queue order. These keys are registered only while hovered, then released on exit, removal, or opening the board for editing. Modified app shortcuts are preserved.
- Click a tab to reveal and focus that exact window. Sifting only positions that replacement window and raises it; background windows are not raised in sequence.
- Drag tabs to reorder the queue. Drop on the left or right half of a tab to insert before or after it. Visible windows stay in their slots. The window list also accepts drag reordering.
- Right-click a tab and choose **Rename tab…** to give it a Lanes label. Names and order survive restarting Lanes while the same app windows remain open; new windows created after reopening the source app have new identities.
- When a category shows multiple windows, the strip shows direct **Top/Bottom** or **Left/Right** buttons for two panes. Hover one to target it without stealing focus, then scroll, use arrows, numbers, or click a tab. A click on the target button focuses its current window. Larger groups use a numbered slot menu. Switching one keeps the others fixed and skips windows pinned in peer slots. Clicking an already visible window focuses its existing slot. Vacant slots retain their geometry.

Each grid region has a **window count** menu in its top-right corner: choose 1–4 windows shown together. Narrow regions show the icon and number; the category and desktop-strip context menus also expose it. Changing the count immediately resizes that region’s managed windows, keeps the selected window when reducing the count, and saves the choice. **Windows shown at once** below the grid and in Preferences controls the same value. With one, the others stay open behind the selected window; switching brings the chosen window forward within that same region. Every collected window is positioned within its category, and Organize does not minimize queued windows. Auto-sort defaults Browser, messaging and previews to one and may show two terminal or simulator windows when they fit. Separate Arc windows are separate entries; browser tabs inside a single window are not. Select Browser and click **Side by side** to show two separate browser windows next to each other; this choice is preserved by Organize.

## Saved layouts and split regions

**Save as preset…** stores your own preset: a named layout with category positions, sizes, active categories, spacing and simultaneous window counts. Your presets appear in the same row as the built-in ones, preview the same way, and survive restart. Duplicate names create a separate numbered copy. Right-click one of your presets to delete it. Trying any preset first saves the current grid; **Back to previous layout** restores it, even after restarting. **Undo grid edit** also reverses resizing, window counts and splitting. Preset selection edits the grid preview; click Apply this grid or Organize to apply it.

Select a category and use the **Split** scissors button, or its context menu, to split left/right or top/bottom. The second region is independently named (for example Browser 2), movable and resizable. If another window is available, it is moved into that region; existing two-pane groups become two independent regions. Split again for more places. Assignments for the same still-open windows survive restarting Lanes.

To add another open app window, select a region and choose **Move window here**, or drag its window-list row onto the region inside Lanes. Refresh the menu if a window just opened. Only the destination and any newly exposed replacement in the source change; peers in other regions stay put. Automatic placement also discovers newly opened windows, keeping category geometry fixed.

## Categories and the shelf

Use **Add category → New named category…** to create a group. Rename through the category context menu. **App categories** above the grid offers an optional review of automatic app grouping, with saved category choices and a reset-to-automatic button for each app. No mandatory onboarding is needed. Assign window rows by drag or their menu; **Always send [app] to** saves an app assignment across launches.

Drag a workspace category into the **Category shelf** below the grid to remove it. Both the category header and sidebar entry can be dragged; dragging the center down into the shelf also works. The shelf highlights as a drop target. Its name and app assignments are preserved. Its windows leave the grid: they are not listed under another category and Lanes does not tile them. Organize moves any that cover a category to the middle of the display. Give such an app a category in **App categories**. A category can mix any apps: in Lanes, open a category's window menu and pick from **Not in any category** or from other categories' windows, or use **Always send [app] to** for every window of an app.

Drag a shelf category back into the workspace to restore it. Drop into a free region to occupy that space, or onto an existing category to split that region. The shelf has a restore context-menu action as well. Selecting a grid section and pressing Backspace also shelves it. Backspace in a text field edits text normally. The final remaining category is protected.

Dragging and dropping categories happens inside Lanes; the app does not install desktop drag targets.

## Window access

Enable Lanes in macOS **Device control and Data access** (called **Accessibility** on older macOS). This lets Lanes read window titles, move and resize windows, and bring selected windows forward. Without it, Lanes still lists running apps, counts them by category, and allows app assignments. App summaries do not pretend to be individual windows.

If Lanes is switched on in Settings but still reports access unavailable (this can happen after replacing Lanes with a copy signed differently, such as your own build), open **Access help**: remove Lanes from the list with the minus button, add it again from Applications, and switch it on.

Lanes uses no screen capture, network requests, or external services. Preferences live in `~/Library/Application Support/Lanes/settings.json`. The app writes its own permission result, version, executable path, and check time to `window-access-state.json`; that diagnostic contains no window titles.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| Hover strip + scroll | Previous/next window in hovered category |
| Hover strip + Left/Right | Previous/next window in hovered category |
| Hover strip + 1…9 / 0 | Select tab 1…9 / 10 |
| Control–Option–Command–Space | Show/hide organizer |
| Right Command twice | Organize (turn off in Preferences) |
| Control–Option–Command–Return | Auto-sort |
| Control–Option–Command–1…7 | Next window in a built-in category (Browser is 7) |
| Control–Option–Command–Tab | Next window in the focused window's category |
| Control–Option–Command–Shift–Tab | Previous window in that category |
| Control–Option–Command–Shift–1…7 | Send focused window to a built-in category |
| Control–Option–Command–arrows | Nudge focused window by 24 pt within its category |
| Control–Option–Command–Shift–arrows | Resize focused window by 24 pt within its category |
| Control–Option–Command–Z | Restore original windows |
| Backspace, with a grid section selected | Move category to shelf |

Double Right Command accepts two quick, clean press/release taps. Holding it or using other shortcuts cancels the sequence. It is configurable in Preferences. Global modifier monitoring uses the existing window-control permission.

## Restore and limits

**Categories follow where windows sit.** A window that fills a category's tile counts in that category, whichever app it belongs to: a new Arc window that opens over the Browser 2 window joins Browser 2, and a window you drag into another category's tile joins it within a few seconds. Floating windows, such as centered new ones, belong to no category.

**New windows** (Preferences) chooses what happens when a window opens. **Center** (the default) opens it centered on the selected display at its own size, shrunk only if it would not fit; nothing else moves, and a new tab stays with its window. **Leave** keeps windows wherever their app opens them. **Category** places each new window into its category after Organize.

**After a restart** (an update, a crash, Force Quit) Lanes picks up the arrangement it finds: windows that already sit in their category's tiles are taken over where they are, nothing moves or comes forward, and the strips return without pressing Organize. Each tile shows the window that is really in front. Windows outside their category wait for automatic placement or Organize.

**Tabs.** Native tabs (Ghostty, Terminal, Finder) are separate windows to macOS: switching tabs hides one and shows another in the same spot. Automatic placement treats that as the same window, so the new tab keeps the old tab's category and slot and no other window is pulled into that tile. Automatic placement never brings forward a window of the app you are typing in, so it cannot take your keyboard.

**Restore**, or normal Quit, restores window frames, minimized states, and originally hidden apps from before the first arrangement. A crash or force quit cannot restore that session snapshot.

Apps impose their own minimum sizes, and some custom windows refuse resizing. Auto-sort adapts once to measured minimum sizes and reports any remaining constraints. Fine window nudges and resizing last until the next arrangement. Mini players are actual compact player or Picture-in-Picture windows; Lanes does not embed streaming players.

Automatic placement is off by default. With **Place new windows in their category automatically** enabled, new windows are positioned after the first Organize. Existing windows and category geometry are kept. Closing a window can reveal a replacement within that slot; it does not trigger full desktop organization. Auto layout is the explicit action for recomputing the whole grid.

## Build and check

Needs macOS 14 or later and the Xcode command-line tools (`xcode-select --install`). No packages to download.

```sh
./build.sh        # quick Apple Silicon build in build/Lanes.app
./test.sh         # 9,000+ model checks plus native strip, grip and discovery tests
./release.sh      # Apple Silicon + Intel build and disk image in dist/ (see RELEASE.md)
```

Without a signing identity, `build.sh` signs your build ad hoc. macOS then treats every rebuild as a new app, so switch Lanes off and on again under Accessibility after each build. For a stable identity, run `./Tools/setup-signing.py --import` once: it creates a local certificate and a dedicated keychain in `.signing/` (never committed) and installs nothing system-wide. Quit the downloaded Lanes before running your own build; both use the same app identifier.

`Tools/StripPreview.swift` renders the strips and the Lanes window offscreen to `build/strip-*.png`, which helps when changing their look.

## Apple API references

- [Code signing requirements and app identity](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- [Local signing certificates](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)
- [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
- [Running applications](https://developer.apple.com/documentation/appkit/nsworkspace/runningapplications)
- [Native mouse dragging](https://developer.apple.com/documentation/appkit/nsresponder/mousedragged(with:))
- [Cursor rectangles](https://developer.apple.com/documentation/appkit/nsview/resetcursorrects())
- [Event monitors](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))
- [Graceful app termination](https://developer.apple.com/documentation/appkit/nsrunningapplication/terminate())
