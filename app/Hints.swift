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
