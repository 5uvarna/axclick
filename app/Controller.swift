// The menu bar item, the global hotkeys, and the three overlay modes: hints (type a label to
// click), search (type an element's text) and scroll (scroll the focused area with keys).

import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class Controller: NSObject {
    enum Mode { case off, hints, search, scroll, grid }

    var mode = Mode.off
    var loading = false

    // Hints and search
    var hints: [Hint] = []
    var typed = ""
    var texts: [String]?        // each hint's visible text, read in the background for search
    var generation = 0          // ignores background text reads for hints that are gone
    var query = ""
    var matches: [Int] = []     // indexes into hints
    var selected = 0

    // Grid: the current region splits into cells named after the keys in the same spot on the
    // keyboard; picking a cell zooms into it. regions[0] is the whole screen.
    var regions: [CGRect] = []

    // Scroll
    var areas: [ScrollArea] = []
    var area = 0

    var windows: [NSWindow] = []
    var views: [OverlayView] = []
    var tap: CFMachPort?
    var statusItem: NSStatusItem?
    var menuItems: [HotKey.Action: NSMenuItem] = [:]
    var hotKeyRefs: [HotKey.Action: EventHotKeyRef] = [:]
    var hotKeyHandlerInstalled = false
    let settings = SettingsWindowController()
    let welcome = WelcomeWindowController()

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "axclick")
        let menu = NSMenu()
        menuItems[.hints] = menu.addItem(withTitle: "Show hints", action: #selector(toggleHints), keyEquivalent: "")
        menuItems[.scroll] = menu.addItem(withTitle: "Scroll mode", action: #selector(toggleScroll), keyEquivalent: "")
        menu.addItem(withTitle: "Grid mode (Space while labels show)", action: #selector(showGrid), keyEquivalent: "").target = self
        menuItems.values.forEach { $0.target = self }
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit axclick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        registerHotKeys()
        if !AXIsProcessTrusted() { welcome.show(); return }
        // Learn which apps have menu bar icons now, so the first labels don't wait for it.
        let pids = NSWorkspace.shared.runningApplications.map { $0.processIdentifier }
        DispatchQueue.global(qos: .utility).async { _ = collectMenuExtras(pids: pids) }
    }

    @objc func openSettings() { settings.show() }

    // MARK: Hotkeys

    func registerHotKeys() {
        HotKey.Action.allCases.forEach { registerHotKey($0) }
    }

    /// Registers the saved shortcut for an action. Returns false if another app already owns it.
    @discardableResult
    func registerHotKey(_ action: HotKey.Action) -> Bool {
        if let ref = hotKeyRefs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
        if !hotKeyHandlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                if let action = HotKey.Action(rawValue: id.id) { controller.hotKeyPressed(action) }
                return noErr
            }, 1, &spec, nil, nil)
            hotKeyHandlerInstalled = true
        }
        let hotKey = HotKey.saved(action)
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4158_434B), id: action.rawValue) // "AXCK"
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if let ref = ref { hotKeyRefs[action] = ref }
        menuItems[action]?.title = "\(action.title) (\(hotKey.description))"
        return status == noErr
    }

    func unregisterHotKeys() {
        hotKeyRefs.values.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs = [:]
    }

    @objc func toggleHints() { hotKeyPressed(.hints) }
    @objc func toggleScroll() { hotKeyPressed(.scroll) }

    /// A shortcut closes its own mode, and switches over from the other one.
    func hotKeyPressed(_ action: HotKey.Action) {
        let current: HotKey.Action? = mode == .off ? nil : (mode == .scroll ? .scroll : .hints)
        if current != nil { hide() }
        if current == action { return }
        guard !loading else { return }
        guard AXIsProcessTrusted(), ensureTap() else { welcome.show(); return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        loading = true
        let pid = app.processIdentifier
        let pids = NSWorkspace.shared.runningApplications.map { $0.processIdentifier }
        DispatchQueue.global(qos: .userInteractive).async {
            if action == .hints {
                // Menu bar icons come from every running app, read alongside the front window.
                var extras: [Target] = []
                let group = DispatchGroup()
                DispatchQueue.global(qos: .userInteractive).async(group: group) { extras = collectMenuExtras(pids: pids) }
                var targets = collectTargets(pid: pid)
                group.wait()
                for e in extras where !targets.contains(where: {
                    abs($0.frame.midX - e.frame.midX) < 6 && abs($0.frame.midY - e.frame.midY) < 6 }) {
                    targets.append(e)
                }
                DispatchQueue.main.async { self.loading = false; self.showHints(targets) }
            } else {
                let areas = collectScrollAreas(pid: pid)
                DispatchQueue.main.async { self.loading = false; self.showScroll(areas) }
            }
        }
    }

    // MARK: Event tap

    /// While an overlay is showing, a keyboard tap swallows keystrokes so the front app keeps
    /// focus (open menus and popovers stay open) without receiving the typed letters.
    func ensureTap() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(mask), callback: { _, type, event, _ in
            controller.handleTap(type: type, event: event)
        }, userInfo: nil)
        guard let tap = tap else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: false)
        return true
    }

    func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if mode != .off, let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard mode != .off else { return Unmanaged.passUnretained(event) }
        if type == .keyDown { handleKey(event) }
        return nil
    }

    func handleKey(_ event: CGEvent) {
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        // Carbon doesn't see the hotkeys while the tap swallows keys, so spot them here.
        for action in HotKey.Action.allCases where HotKey.saved(action).matches(keyCode: code, flags: flags) {
            hotKeyPressed(action)
            return
        }
        if code == kVK_Escape { hide(); return }
        switch mode {
        case .hints: hintKey(code: code, flags: flags, event: event)
        case .search: searchKey(code: code, flags: flags, event: event)
        case .scroll: scrollKey(code: code, flags: flags, event: event)
        case .grid: gridKey(code: code, flags: flags, event: event)
        case .off: break
        }
    }

    // MARK: Overlay windows

    var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// An accessibility point (top-left origin) in Cocoa coordinates (bottom-left origin).
    func cocoa(_ p: CGPoint) -> NSPoint { NSPoint(x: p.x, y: primaryHeight - p.y) }
    func cocoa(_ r: CGRect) -> NSRect { NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height) }

    func openOverlay() {
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.setFrame(screen.frame, display: false)
            let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
            views.append(view)
        }
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Redraws every screen's overlay from the current mode and state.
    func render() {
        for (window, view) in zip(windows, views) {
            let origin = window.frame.origin
            let local = { (p: NSPoint) in NSPoint(x: p.x - origin.x, y: p.y - origin.y) }
            view.labels = []
            view.boxes = []
            view.cells = []
            view.tint = false
            view.dot = nil
            view.banner = nil
            view.typed = ""
            var focus: NSPoint?   // where the banner belongs: the screen with the thing in focus

            switch mode {
            case .hints:
                view.typed = typed
                for h in hints {
                    let p = cocoa(CGPoint(x: h.target.frame.minX, y: h.target.frame.midY))
                    if window.frame.contains(p) { view.labels.append(.init(text: h.label, point: local(p))) }
                }
            case .search:
                for (i, index) in matches.enumerated() {
                    let t = hints[index].target
                    let p = cocoa(CGPoint(x: t.frame.minX, y: t.frame.midY))
                    if i == selected { focus = p }
                    if window.frame.contains(p) {
                        view.labels.append(.init(text: hints[index].label, point: local(p), selected: i == selected))
                    }
                }
                if focus == nil, let first = hints.first { focus = cocoa(CGPoint(x: first.target.frame.midX, y: first.target.frame.midY)) }
                if let f = focus, window.frame.contains(f) || NSScreen.screens.count == 1 {
                    let count = matches.isEmpty ? "no matches" : matches.count == 1 ? "1 match" : "\(matches.count) matches"
                    view.banner = "Search: \(query)▏  \(count)   ↩ click  ⇥ next  ⌫ back"
                }
            case .scroll:
                for (i, a) in areas.enumerated() {
                    let r = cocoa(a.frame)
                    if i == area { focus = NSPoint(x: r.midX, y: r.midY) }
                    guard window.frame.intersects(r) else { continue }
                    view.boxes.append((NSRect(origin: local(r.origin), size: r.size), i == area))
                    if areas.count > 1 {
                        view.labels.append(.init(text: "\(i + 1)", point: local(NSPoint(x: r.minX + 8, y: r.maxY - 16)), selected: i == area))
                    }
                }
                if let f = focus, window.frame.contains(f) || NSScreen.screens.count == 1 {
                    view.banner = "Scroll   j k  h l   d u half page   g G top/bottom"
                        + (areas.count > 1 ? "   1–\(areas.count) area" : "") + "   esc done"
                }
            case .grid:
                guard let region = regions.last else { break }
                for c in gridSplit(region) {
                    let r = cocoa(c.rect)
                    guard window.frame.intersects(r) else { continue }
                    view.cells.append(NSRect(origin: local(r.origin), size: r.size))
                    view.labels.append(.init(text: c.label, point: local(NSPoint(x: r.midX, y: r.midY)), centered: true, faint: true))
                }
                let r = cocoa(region)
                let center = NSPoint(x: r.midX, y: r.midY)
                if window.frame.intersects(r) {
                    view.boxes.append((NSRect(origin: local(r.origin), size: r.size), true))
                    view.dot = local(center)
                }
                if window.frame.contains(center) {
                    let screens = NSScreen.screens.count > 1 ? "   1–\(NSScreen.screens.count) screen" : ""
                    view.banner = "Pick a cell to zoom in   ↩ click the dot   ⌫ back" + screens + "   esc cancel"
                }
            case .off:
                break
            }
            view.needsDisplay = true
        }
    }

    func hide() {
        mode = .off
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        windows.forEach { $0.orderOut(nil) }
        windows = []
        views = []
        hints = []
        typed = ""
        texts = nil
        query = ""
        matches = []
        areas = []
        regions = []
        generation += 1
    }

    // MARK: Hints

    func showHints(_ targets: [Target]) {
        // Nothing to label (a game, a canvas, a remote desktop): offer the grid instead.
        guard !targets.isEmpty else { showGrid(); return }
        // Reading order (rows, then left to right) keeps labels predictable.
        let sorted = targets.sorted {
            let r0 = Int($0.frame.midY / 12), r1 = Int($1.frame.midY / 12)
            return r0 != r1 ? r0 < r1 : $0.frame.minX < $1.frame.minX
        }
        hints = zip(labels(count: sorted.count), sorted).map { Hint(label: $0, target: $1) }
        typed = ""
        mode = .hints
        openOverlay()
        render()

        // Read element text for search in the background, so labels appear without waiting for it.
        let gen = generation
        let refs = hints.map { $0.target.ref }
        DispatchQueue.global(qos: .userInitiated).async {
            let texts = refs.map(elementText)
            DispatchQueue.main.async {
                guard self.generation == gen, self.texts == nil else { return }
                self.texts = texts
                if self.mode == .search { self.updateMatches() }
            }
        }
    }

    func hintKey(code: Int, flags: CGEventFlags, event: CGEvent) {
        if code == kVK_Delete {
            if !typed.isEmpty { typed.removeLast(); render() }
            return
        }
        if NSEvent(cgEvent: event)?.characters == "/" { startSearch(); return }
        if code == kVK_Space { showGrid(); return }
        guard let chars = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.uppercased(),
              let c = chars.first, hintAlphabet.contains(c) else { return }
        let candidate = typed + String(c)
        let found = hints.filter { $0.label.hasPrefix(candidate) }
        guard !found.isEmpty else { NSSound.beep(); return }
        typed = candidate
        render()
        if let hit = found.first(where: { $0.label == candidate }) { finishClick(hit.target, flags: flags) }
    }

    func finishClick(_ target: Target, flags: CGEventFlags) {
        hide()
        // Let the overlay disappear before the click lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.click(target, flags: flags) }
    }

    func click(_ t: Target, flags: CGEventFlags) {
        let center = CGPoint(x: t.frame.midX, y: t.frame.midY)
        if flags.contains(.maskShift) {
            postClick(at: center, right: true)
        } else if flags.contains(.maskCommand) {
            postClick(at: center, flags: .maskCommand)
        } else if realClickRoles.contains(t.role)
                    || AXUIElementPerformAction(t.ref, kAXPressAction as CFString) != .success {
            postClick(at: center)
        }
    }

    // MARK: Search

    func startSearch() {
        mode = .search
        query = ""
        typed = ""
        updateMatches()
    }

    /// Lowercased, without accents or punctuation, so "wifi" finds "Wi‑Fi" and "cafe" finds "Café".
    func searchable(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        let kept = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        return String(String.UnicodeScalarView(kept)).split(separator: " ").joined(separator: " ")
    }

    func updateMatches() {
        let q = searchable(query)
        if q.isEmpty || texts == nil {
            matches = q.isEmpty ? Array(hints.indices) : []
        } else {
            let lowered = texts!.map(searchable)
            // Exact matches first, then matches at the start of a word, then anywhere.
            func quality(_ t: String) -> Int? {
                if t == q { return 0 }
                if t.hasPrefix(q) || t.contains(" " + q) { return 1 }
                return t.contains(q) ? 2 : nil
            }
            // Within each, an open menu first, then the window, then the menu bar (whose "History"
            // or "View" would otherwise win just by being at the top of the screen).
            func place(_ role: String) -> Int { role == "AXMenuItem" ? 0 : role == "AXMenuBarItem" ? 2 : 1 }
            matches = lowered.indices
                .compactMap { i in quality(lowered[i]).map { (i, $0, place(hints[i].target.role)) } }
                .sorted { ($0.1, $0.2, $0.0) < ($1.1, $1.2, $1.0) }
                .map { $0.0 }
        }
        selected = 0
        render()
    }

    func searchKey(code: Int, flags: CGEventFlags, event: CGEvent) {
        switch code {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard selected < matches.count else { NSSound.beep(); return }
            finishClick(hints[matches[selected]].target, flags: flags)
        case kVK_Tab, kVK_DownArrow, kVK_RightArrow:
            guard !matches.isEmpty else { return }
            let back = code == kVK_Tab && flags.contains(.maskShift)
            selected = (selected + (back ? matches.count - 1 : 1)) % matches.count
            render()
        case kVK_UpArrow, kVK_LeftArrow:
            guard !matches.isEmpty else { return }
            selected = (selected + matches.count - 1) % matches.count
            render()
        case kVK_Delete:
            if query.isEmpty {
                mode = .hints // back to typing labels
                render()
            } else {
                query.removeLast()
                updateMatches()
            }
        default:
            guard !flags.contains(.maskCommand), !flags.contains(.maskControl),
                  let chars = NSEvent(cgEvent: event)?.characters, !chars.isEmpty,
                  chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return }
            query += chars
            updateMatches()
        }
    }

    // MARK: Grid

    /// Starts on the screen with the pointer. Number keys switch screens.
    @objc func showGrid() {
        if mode == .off {
            guard AXIsProcessTrusted(), ensureTap() else { welcome.show(); return }
            openOverlay()
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.screens.first
        regions = screen.map { [topLeft($0.frame)] } ?? []
        typed = ""
        mode = .grid
        render()
    }

    /// A Cocoa screen frame (bottom-left origin) in the top-left space that clicks use.
    func topLeft(_ f: NSRect) -> CGRect { CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height) }

    /// Splits a region 4×3 on Q W E R / A S D F / Z X C V, so each letter sits where its key is
    /// on the keyboard. Four columns make cells small enough to click after three keys.
    func gridSplit(_ r: CGRect) -> [(label: String, rect: CGRect)] {
        let rows = [["Q", "W", "E", "R"], ["A", "S", "D", "F"], ["Z", "X", "C", "V"]]
        let h = r.height / CGFloat(rows.count), w = r.width / CGFloat(rows[0].count)
        return rows.enumerated().flatMap { (y, row) in
            row.enumerated().map { (x, key) in
                (label: key, rect: CGRect(x: r.minX + CGFloat(x) * w, y: r.minY + CGFloat(y) * h, width: w, height: h))
            }
        }
    }

    func gridKey(code: Int, flags: CGEventFlags, event: CGEvent) {
        guard let region = regions.last else { return }
        if code == kVK_Delete {
            if regions.count > 1 { regions.removeLast(); render() }
            return
        }
        if code == kVK_Return || code == kVK_Space || code == kVK_ANSI_KeypadEnter {
            gridClick(CGPoint(x: region.midX, y: region.midY), flags: flags)
            return
        }
        let key = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.uppercased() ?? ""
        if let n = Int(key), n >= 1, n <= NSScreen.screens.count {
            regions = [topLeft(NSScreen.screens[n - 1].frame)]
            render()
            return
        }
        guard let cell = gridSplit(region).first(where: { $0.label == key }) else { NSSound.beep(); return }
        regions.append(cell.rect)
        // A cell under 45 points hits almost any button at its middle, so click without waiting
        // for Return. That's the third key on a laptop or 1080p screen, the fourth on bigger ones.
        if cell.rect.width < 45 && cell.rect.height < 45 {
            gridClick(CGPoint(x: cell.rect.midX, y: cell.rect.midY), flags: flags)
            return
        }
        render()
    }

    func gridClick(_ p: CGPoint, flags: CGEventFlags) {
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if flags.contains(.maskShift) {
                postClick(at: p, right: true)
            } else {
                postClick(at: p, flags: flags.contains(.maskCommand) ? .maskCommand : [])
            }
        }
    }

    // MARK: Scroll

    func showScroll(_ found: [ScrollArea]) {
        guard !found.isEmpty else { NSSound.beep(); return }
        areas = found
        area = 0
        mode = .scroll
        openOverlay()
        render()
    }

    func scrollKey(code: Int, flags: CGEventFlags, event: CGEvent) {
        guard area < areas.count else { return }
        let a = areas[area].frame
        let fast: CGFloat = flags.contains(.maskShift) ? 3 : 1
        let step = 60 * fast
        let page = a.height * 0.5
        let key = NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? ""
        var dx: CGFloat = 0, dy: CGFloat = 0

        switch (code, key) {
        case (kVK_DownArrow, _), (_, "j"), (_, "J"): dy = step
        case (kVK_UpArrow, _), (_, "k"), (_, "K"): dy = -step
        case (kVK_LeftArrow, _), (_, "h"), (_, "H"): dx = -step
        case (kVK_RightArrow, _), (_, "l"), (_, "L"): dx = step
        case (_, "d"), (kVK_PageDown, _): dy = page
        case (_, "u"), (kVK_PageUp, _): dy = -page
        case (_, "g"), (_, "G"):
            jump(toEnd: key == "G" || flags.contains(.maskShift)); return
        case (kVK_Tab, _):
            area = (area + (flags.contains(.maskShift) ? areas.count - 1 : 1)) % areas.count
            render(); return
        default:
            if let n = Int(key), n >= 1, n <= areas.count { area = n - 1; render() }
            return
        }
        smoothScroll(at: CGPoint(x: a.midX, y: a.midY), dx: dx, dy: dy)
    }

    /// Top or bottom. Huge scroll events can stall an app (Finder spins on them), so without a
    /// scroll bar to set, this posts a burst of page-sized scrolls instead.
    func jump(toEnd: Bool) {
        let a = areas[area]
        if jumpScrollBar(a.ref, toEnd: toEnd) { return }
        let p = CGPoint(x: a.frame.midX, y: a.frame.midY)
        let page = Int32(max(a.frame.height, 300)) * (toEnd ? 1 : -1)
        for i in 0..<40 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.01) { postScroll(at: p, dx: 0, dy: page) }
        }
    }

    /// Splits a scroll into a few small steps so it glides instead of jumping.
    func smoothScroll(at p: CGPoint, dx: CGFloat, dy: CGFloat) {
        let steps = 5
        for i in 0..<steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.012) {
                postScroll(at: p, dx: Int32(dx / CGFloat(steps)), dy: Int32(dy / CGFloat(steps)))
            }
        }
    }
}
