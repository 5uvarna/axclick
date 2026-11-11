// axclick: keyboard clicking for macOS.
//
// Press ⌘⇧Space and a label appears on every clickable element of the front app.
// Type a label to click that element. Shift + last letter right-clicks, ⌘ + last letter
// ⌘-clicks, Backspace removes a letter, Esc (or ⌘⇧Space again) cancels.
//
// Elements come from the Accessibility API, so clicks land on the element itself
// (AXPress), or on its exact center when an element has no press action.

import AppKit
import ApplicationServices
import Carbon.HIToolbox

let hotKeyCode = UInt32(kVK_Space)
let hotKeyModifiers = UInt32(cmdKey | shiftKey)
let hotKeyDescription = "⌘⇧Space"

// Home-row keys first, so most labels are quick to type.
let hintAlphabet = Array("ASDFJKLGHQWERUIOPTYZXCVBNM")

let clickableRoles: Set<String> = [
    "AXButton", "AXLink", "AXMenuItem", "AXMenuBarItem", "AXCheckBox", "AXRadioButton",
    "AXPopUpButton", "AXMenuButton", "AXTextField", "AXTextArea", "AXSearchField",
    "AXComboBox", "AXTab", "AXDisclosureTriangle", "AXCell", "AXSlider", "AXIncrementor",
    "AXColorWell", "AXSegmentedControl",
]
// Generic roles that count only when they expose a press action (e.g. clickable divs in Chrome).
let pressCheckRoles: Set<String> = ["AXGroup", "AXImage", "AXStaticText", "AXGenericElement"]
// Roles where a real mouse click works better than AXPress (it places focus and the caret).
let realClickRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXCell"]

let collectBudget: TimeInterval = 1.5
let maxNodes = 6000

// MARK: - Accessibility

struct Target {
    let ref: AXUIElement
    let role: String
    let frame: CGRect // global, top-left origin (same space as CGEvent)
}

func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
    return value as? T
}

func axValue<T>(_ v: AnyObject?, _ type: AXValueType, _ empty: T) -> T? {
    guard let v = v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    let axv = v as! AXValue
    guard AXValueGetType(axv) == type else { return nil }
    var out = empty
    return AXValueGetValue(axv, type, &out) ? out : nil
}

/// Role, frame and children in one round trip; separate calls make walking 4x slower.
func info(_ el: AXUIElement) -> (role: String, frame: CGRect?, children: [AXUIElement]) {
    let names = [kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute,
                 kAXVisibleChildrenAttribute, kAXChildrenAttribute] as CFArray
    var values: CFArray?
    guard AXUIElementCopyMultipleAttributeValues(el, names, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
          let v = values as? [AnyObject], v.count == 5 else { return ("", nil, []) }
    let role = v[0] as? String ?? ""
    var frame: CGRect?
    if let p = axValue(v[1], .cgPoint, CGPoint.zero), let s = axValue(v[2], .cgSize, CGSize.zero) {
        frame = CGRect(origin: p, size: s)
    }
    // Lists and tables expose only on-screen rows as visible children.
    let children = (v[3] as? [AXUIElement]) ?? (v[4] as? [AXUIElement]) ?? []
    return (role, frame, children)
}

func hasPress(_ el: AXUIElement) -> Bool {
    var names: CFArray?
    AXUIElementCopyActionNames(el, &names)
    return ((names as? [String]) ?? []).contains(kAXPressAction)
}

func collectTargets(pid: pid_t) -> [Target] {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.3)
    // Chromium and Electron apps only build their accessibility tree when asked to.
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

    var out: [Target] = []
    var nodes = 0
    let deadline = Date().addingTimeInterval(collectBudget)

    func add(_ el: AXUIElement, _ role: String, _ f: CGRect) {
        guard f.width >= 4, f.height >= 4 else { return }
        // A link wrapping a button, a cell inside a row: keep one label per spot.
        if out.contains(where: { abs($0.frame.midX - f.midX) < 6 && abs($0.frame.midY - f.midY) < 6 }) { return }
        out.append(Target(ref: el, role: role, frame: f))
    }

    func walk(_ el: AXUIElement, depth: Int, clip: CGRect?) {
        guard depth < 60, nodes < maxNodes, Date() < deadline else { return }
        nodes += 1
        let (role, frame, children) = info(el)
        if let f = frame, let clip = clip, f.width > 0, f.height > 0, !f.intersects(clip) {
            return // scrolled out of view, and so is everything inside it
        }
        if let f = frame, clickableRoles.contains(role) || (pressCheckRoles.contains(role) && hasPress(el)) {
            add(el, role, clip.map { f.intersection($0) } ?? f)
        }
        for child in children { walk(child, depth: depth + 1, clip: clip) }
    }

    // Menu bar: top-level items, plus the contents of a menu that is open.
    if let menuBar: AXUIElement = attr(app, kAXMenuBarAttribute) {
        for item in info(menuBar).children {
            let (role, frame, children) = info(item)
            if let f = frame { add(item, role, f) }
            if (attr(item, kAXSelectedAttribute) as Bool?) == true {
                for child in children { walk(child, depth: 1, clip: nil) }
            }
        }
    }

    // The focused window, plus popovers, sheets and dialogs floating over it.
    let focused: AXUIElement? = attr(app, kAXFocusedWindowAttribute)
    var windows: [AXUIElement] = focused.map { [$0] } ?? []
    for w in (attr(app, kAXWindowsAttribute) as [AXUIElement]?) ?? [] {
        if let focused = focused, CFEqual(w, focused) { continue }
        if (attr(w, kAXSubroleAttribute) as String?) != kAXStandardWindowSubrole { windows.append(w) }
    }
    for w in windows {
        walk(w, depth: 0, clip: info(w).frame)
    }
    return out
}

func postClick(at p: CGPoint, right: Bool = false, flags: CGEventFlags = []) {
    let src = CGEventSource(stateID: .hidSystemState)
    let (down, up, button): (CGEventType, CGEventType, CGMouseButton) =
        right ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
    for type in [CGEventType.mouseMoved, down, up] {
        let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: button)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
        usleep(20_000)
    }
}

// MARK: - Overlay

struct Hint {
    let label: String
    let target: Target
}

final class HintView: NSView {
    var hints: [(label: String, point: NSPoint)] = [] // point: left edge, vertical center
    var typed = "" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        for h in hints where h.label.hasPrefix(typed) {
            let text = NSMutableAttributedString(string: h.label, attributes: [.font: font, .foregroundColor: NSColor.black])
            if !typed.isEmpty {
                text.addAttribute(.foregroundColor, value: NSColor.black.withAlphaComponent(0.35),
                                  range: NSRange(location: 0, length: typed.count))
            }
            let size = text.size()
            var box = NSRect(x: h.point.x, y: h.point.y - (size.height + 4) / 2, width: size.width + 8, height: size.height + 4)
            box.origin.x = min(max(box.minX, bounds.minX), bounds.maxX - box.width)
            box.origin.y = min(max(box.minY, bounds.minY), bounds.maxY - box.height)
            let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            NSColor(calibratedRed: 1, green: 0.85, blue: 0.25, alpha: 0.95).setFill()
            path.fill()
            NSColor.black.withAlphaComponent(0.45).setStroke()
            path.stroke()
            text.draw(at: NSPoint(x: box.minX + 4, y: box.minY + 2))
        }
    }
}

func labels(count: Int) -> [String] {
    let k = hintAlphabet.count
    var length = 1
    while Int(pow(Double(k), Double(length))) < count { length += 1 }
    // Fixed length keeps labels prefix-free, so a label fires as soon as it is complete.
    return (0..<count).map { i in
        var n = i, s = ""
        for _ in 0..<length { s = String(hintAlphabet[n % k]) + s; n /= k }
        return s
    }
}

// MARK: - Controller

final class Controller: NSObject {
    var hints: [Hint] = []
    var typed = ""
    var windows: [NSWindow] = []
    var views: [HintView] = []
    var active = false
    var loading = false
    var tap: CFMachPort?
    var statusItem: NSStatusItem?

    func setup() {
        registerHotKey()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "axclick")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show hints (\(hotKeyDescription))", action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit axclick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
    }

    func registerHotKey() {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4158_434B), id: 1) // "AXCK"
        RegisterEventHotKey(hotKeyCode, hotKeyModifiers, id, GetApplicationEventTarget(), 0, &ref)
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            controller.toggle()
            return noErr
        }, 1, &spec, nil, nil)
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
        guard AXIsProcessTrusted(), ensureTap() else {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
            return
        }
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
        if code == kVK_Space && flags.contains(.maskCommand) && flags.contains(.maskShift) { hide(); return }
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

// MARK: - Main

let controller = Controller()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
controller.setup()
app.run()
