// The menu bar item, the global hotkey, and showing, typing and clicking hints.

import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class Controller: NSObject {
    var hints: [Hint] = []
    var typed = ""
    var windows: [NSWindow] = []
    var views: [HintView] = []
    var active = false
    var loading = false
    var tap: CFMachPort?
    var statusItem: NSStatusItem?
    var showItem: NSMenuItem?
    var hotKeyRef: EventHotKeyRef?
    var hotKeyHandlerInstalled = false
    let settings = SettingsWindowController()
    let welcome = WelcomeWindowController()

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "axclick")
        let menu = NSMenu()
        showItem = menu.addItem(withTitle: "Show hints", action: #selector(toggle), keyEquivalent: "")
        showItem?.target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit axclick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        registerHotKey()
        if !AXIsProcessTrusted() { welcome.show() }
    }

    @objc func openSettings() { settings.show() }

    /// Registers the saved hotkey. Returns false if another app already owns that shortcut.
    @discardableResult
    func registerHotKey() -> Bool {
        unregisterHotKey()
        let hotKey = HotKey.saved
        let id = EventHotKeyID(signature: OSType(0x4158_434B), id: 1) // "AXCK"
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if !hotKeyHandlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                controller.toggle()
                return noErr
            }, 1, &spec, nil, nil)
            hotKeyHandlerInstalled = true
        }
        showItem?.title = "Show hints (\(hotKey.description))"
        return status == noErr
    }

    func unregisterHotKey() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        hotKeyRef = nil
    }

    /// While hints are showing, a keyboard tap swallows keystrokes so the front app keeps
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

    @objc func toggle() {
        if active { hide(); return }
        guard !loading else { return }
        guard AXIsProcessTrusted(), ensureTap() else { welcome.show(); return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        loading = true
        let pid = app.processIdentifier
        DispatchQueue.global(qos: .userInteractive).async {
            let targets = collectTargets(pid: pid)
            DispatchQueue.main.async {
                self.loading = false
                self.show(targets)
            }
        }
    }

    func show(_ targets: [Target]) {
        guard !targets.isEmpty else { NSSound.beep(); return }
        // Reading order (rows, then left to right) keeps labels predictable.
        let sorted = targets.sorted {
            let r0 = Int($0.frame.midY / 12), r1 = Int($1.frame.midY / 12)
            return r0 != r1 ? r0 < r1 : $0.frame.minX < $1.frame.minX
        }
        hints = zip(labels(count: sorted.count), sorted).map { Hint(label: $0, target: $1) }
        typed = ""

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.setFrame(screen.frame, display: false)
            let view = HintView(frame: NSRect(origin: .zero, size: screen.frame.size))
            for h in hints {
                // Accessibility frames are top-left based; Cocoa screens are bottom-left based.
                let p = NSPoint(x: h.target.frame.minX, y: primaryHeight - h.target.frame.midY)
                if screen.frame.contains(p) {
                    view.hints.append((h.label, NSPoint(x: p.x - screen.frame.minX, y: p.y - screen.frame.minY)))
                }
            }
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
            views.append(view)
        }
        active = true
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    func hide() {
        active = false
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        windows.forEach { $0.orderOut(nil) }
        windows = []
        views = []
        hints = []
        typed = ""
    }

    func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if active, let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard active else { return Unmanaged.passUnretained(event) }
        if type == .keyDown { handleKey(event) }
        return nil
    }

    func handleKey(_ event: CGEvent) {
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        // The hotkey itself toggles hints off; Carbon doesn't see it while the tap swallows keys.
        let hotKey = HotKey.saved
        let modifiers = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        if code == Int(hotKey.keyCode) && modifiers == hotKey.cgFlags { hide(); return }
        if code == kVK_Escape { hide(); return }
        if code == kVK_Delete {
            if !typed.isEmpty { typed.removeLast(); views.forEach { $0.typed = typed } }
            return
        }
        guard let chars = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.uppercased(),
              let c = chars.first, hintAlphabet.contains(c) else { return }
        let candidate = typed + String(c)
        let matches = hints.filter { $0.label.hasPrefix(candidate) }
        guard !matches.isEmpty else { NSSound.beep(); return }
        typed = candidate
        views.forEach { $0.typed = typed }
        if let hit = matches.first(where: { $0.label == candidate }) {
            hide()
            // Let the overlay disappear before the click lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.click(hit.target, flags: flags) }
        }
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
}
