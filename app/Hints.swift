// Finding clickable elements through the Accessibility API, clicking them, and drawing labels.

import AppKit
import ApplicationServices

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

func axAXValue(_ v: AnyObject?, _ type: AXValueType) -> AXValue? {
    guard let v = v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    let axv = v as! AXValue
    return AXValueGetType(axv) == type ? axv : nil
}

func axPoint(_ v: AnyObject?) -> CGPoint? {
    guard let axv = axAXValue(v, .cgPoint) else { return nil }
    var p = CGPoint.zero
    return AXValueGetValue(axv, .cgPoint, &p) ? p : nil
}

func axSize(_ v: AnyObject?) -> CGSize? {
    guard let axv = axAXValue(v, .cgSize) else { return nil }
    var s = CGSize.zero
    return AXValueGetValue(axv, .cgSize, &s) ? s : nil
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
    if let p = axPoint(v[1]), let s = axSize(v[2]) {
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

// MARK: - Search text and scroll areas

/// The words a person sees on an element, for search: its title, description, placeholder,
/// help text or value, or else the text inside it (Chrome puts link text in child elements).
func elementText(_ el: AXUIElement) -> String {
    func strings(_ e: AXUIElement) -> [String] {
        let names = [kAXTitleAttribute, kAXDescriptionAttribute, "AXPlaceholderValue", kAXHelpAttribute, kAXValueAttribute] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(e, names, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
              let v = values as? [AnyObject] else { return [] }
        return v.compactMap { $0 as? String }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var parts = strings(el)
    if parts.isEmpty {
        var queue: [(AXUIElement, Int)] = ((attr(el, kAXChildrenAttribute) as [AXUIElement]?) ?? []).map { ($0, 1) }
        var visited = 0
        while !queue.isEmpty, visited < 12, parts.count < 3 {
            let (e, depth) = queue.removeFirst()
            visited += 1
            parts += strings(e)
            if depth < 3 { queue += ((attr(e, kAXChildrenAttribute) as [AXUIElement]?) ?? []).map { ($0, depth + 1) } }
        }
    }
    // Chrome often repeats a link's name as its title and description.
    var seen = Set<String>()
    parts = parts.filter { seen.insert($0.lowercased()).inserted }
    return String(parts.joined(separator: " ").prefix(200))
}

struct ScrollArea {
    let ref: AXUIElement
    let frame: CGRect
}

/// Scrollable areas in the focused window, largest first. Falls back to the window itself.
func collectScrollAreas(pid: pid_t) -> [ScrollArea] {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.3)
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    guard let window: AXUIElement = attr(app, kAXFocusedWindowAttribute),
          let windowFrame = info(window).frame else { return [] }

    var out: [ScrollArea] = []
    var nodes = 0
    let deadline = Date().addingTimeInterval(1.0)
    func walk(_ el: AXUIElement, depth: Int) {
        guard depth < 60, nodes < maxNodes, Date() < deadline else { return }
        nodes += 1
        let (role, frame, children) = info(el)
        if let f = frame, f.width > 0, f.height > 0, !f.intersects(windowFrame) { return }
        if role == "AXScrollArea" || role == "AXWebArea", let f = frame?.intersection(windowFrame),
           f.width >= 60, f.height >= 60,
           !out.contains(where: { abs($0.frame.minX - f.minX) < 4 && abs($0.frame.minY - f.minY) < 4
                                   && abs($0.frame.maxX - f.maxX) < 4 && abs($0.frame.maxY - f.maxY) < 4 }) {
            out.append(ScrollArea(ref: el, frame: f))
        }
        for child in children { walk(child, depth: depth + 1) }
    }
    walk(window, depth: 0)
    if out.isEmpty { out = [ScrollArea(ref: window, frame: windowFrame)] }
    return Array(out.sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }.prefix(9))
}

/// Jumps an area to its top or bottom by setting its vertical scroll bar. Returns false when the
/// area has no settable scroll bar (web pages, for example).
func jumpScrollBar(_ area: AXUIElement, toEnd: Bool) -> Bool {
    let bar: AXUIElement? = attr(area, kAXVerticalScrollBarAttribute)
        ?? ((attr(area, kAXChildrenAttribute) as [AXUIElement]?) ?? []).first {
            (attr($0, kAXRoleAttribute) as String?) == kAXScrollBarRole
                && (attr($0, kAXOrientationAttribute) as String?) == kAXVerticalOrientationValue
        }
    guard let bar = bar else { return false }
    return AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: toEnd ? 1.0 : 0.0)) == .success
}

/// Posts a scroll at a point without moving the pointer. Positive dy scrolls down, positive dx right.
func postScroll(at p: CGPoint, dx: Int32, dy: Int32) {
    let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: -dy, wheel2: -dx, wheel3: 0)
    e?.location = p
    e?.post(tap: .cghidEventTap)
}

// MARK: - Overlay

struct Hint {
    let label: String
    let target: Target
}

/// One screen's overlay: yellow labels, outlined areas (scroll mode) and a status banner.
final class OverlayView: NSView {
    struct Label { var text: String; var point: NSPoint; var selected = false } // point: left edge, vertical center
    var labels: [Label] = []
    var boxes: [(rect: NSRect, selected: Bool)] = []
    var typed = ""         // dims the typed part of each label and hides labels that don't match
    var banner: String?

    override func draw(_ dirtyRect: NSRect) {
        for b in boxes {
            let path = NSBezierPath(roundedRect: b.rect.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
            path.lineWidth = b.selected ? 4 : 2
            if !b.selected { path.setLineDash([6, 4], count: 2, phase: 0) }
            (b.selected ? NSColor.systemBlue : NSColor.systemGray).withAlphaComponent(0.9).setStroke()
            path.stroke()
        }

        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        for l in labels where l.text.hasPrefix(typed) {
            let fg: NSColor = l.selected ? .white : .black
            let text = NSMutableAttributedString(string: l.text, attributes: [.font: font, .foregroundColor: fg])
            if !typed.isEmpty {
                text.addAttribute(.foregroundColor, value: fg.withAlphaComponent(0.35), range: NSRange(location: 0, length: typed.count))
            }
            let size = text.size()
            var box = NSRect(x: l.point.x, y: l.point.y - (size.height + 4) / 2, width: size.width + 8, height: size.height + 4)
            box.origin.x = min(max(box.minX, bounds.minX), bounds.maxX - box.width)
            box.origin.y = min(max(box.minY, bounds.minY), bounds.maxY - box.height)
            let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            (l.selected ? NSColor.systemBlue : NSColor(calibratedRed: 1, green: 0.85, blue: 0.25, alpha: 0.95)).setFill()
            path.fill()
            NSColor.black.withAlphaComponent(0.45).setStroke()
            path.stroke()
            text.draw(at: NSPoint(x: box.minX + 4, y: box.minY + 2))
        }

        if let banner = banner {
            let text = NSAttributedString(string: banner, attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white])
            let size = text.size()
            let box = NSRect(x: bounds.midX - size.width / 2 - 14, y: bounds.minY + 80, width: size.width + 28, height: size.height + 16)
            NSColor.black.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
            text.draw(at: NSPoint(x: box.minX + 14, y: box.minY + 8))
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
