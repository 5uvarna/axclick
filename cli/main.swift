// axclick: Homerow-style precise clicking through the macOS Accessibility API.
//
//   axclick check                      exit 0 if Accessibility access is granted
//   axclick list  [app] [filter]       list clickable elements (id, role, label, frame)
//   axclick press [app] <id>           press element by id (AXPress, falls back to a click at its center)
//   axclick find  [app] <text>         press the first element whose label contains text
//
// [app] is an app name ("Google Chrome") or "front" for the frontmost app (the default).
// Ids are traversal indices, so they stay valid only while the UI is unchanged.

import AppKit
import ApplicationServices

let clickableRoles: Set<String> = [
    "AXButton", "AXLink", "AXMenuItem", "AXMenuBarItem", "AXCheckBox", "AXRadioButton",
    "AXPopUpButton", "AXMenuButton", "AXTextField", "AXTextArea", "AXSearchField",
    "AXComboBox", "AXTab", "AXDisclosureTriangle", "AXCell", "AXRow", "AXSlider",
    "AXIncrementor", "AXColorWell", "AXDockItem",
]

struct Element {
    let id: Int
    let ref: AXUIElement
    let role: String
    let label: String
    let frame: CGRect?
}

func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
    return value as? T
}

func frame(of el: AXUIElement) -> CGRect? {
    guard let posVal: AXValue = attr(el, kAXPositionAttribute),
          let sizeVal: AXValue = attr(el, kAXSizeAttribute) else { return nil }
    var pos = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(posVal, .cgPoint, &pos)
    AXValueGetValue(sizeVal, .cgSize, &size)
    return CGRect(origin: pos, size: size)
}

func label(of el: AXUIElement) -> String {
    for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute,
                 kAXPlaceholderValueAttribute as String, "AXIdentifier"] {
        if let s: String = attr(el, name), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s.replacingOccurrences(of: "\n", with: " ")
        }
    }
    // Fall back to the text of static-text children, e.g. a link wrapping a label.
    let children: [AXUIElement] = attr(el, kAXChildrenAttribute) ?? []
    let texts = children.compactMap { child -> String? in
        (attr(child, kAXRoleAttribute) as String?) == "AXStaticText" ? attr(child, kAXValueAttribute) : nil
    }
    return texts.joined(separator: " ")
}

// Large trees (Finder, browsers) can take minutes to walk in full, so cap the walk.
let timeBudget: TimeInterval = 6
let maxNodes = 8000

func children(of el: AXUIElement) -> [AXUIElement] {
    // Lists and tables expose only on-screen rows here, which avoids walking thousands of items.
    if let visible: [AXUIElement] = attr(el, kAXVisibleChildrenAttribute) { return visible }
    return attr(el, kAXChildrenAttribute) ?? []
}

func collect(app: AXUIElement) -> [Element] {
    var out: [Element] = []
    var counter = 0
    var seen = 0
    let deadline = Date().addingTimeInterval(timeBudget)
    func walk(_ el: AXUIElement, depth: Int, maxDepth: Int = 60) {
        seen += 1
        guard depth < maxDepth, seen < maxNodes, Date() < deadline else { return }
        let role: String = attr(el, kAXRoleAttribute) ?? ""
        let actions: [String] = {
            var names: CFArray?
            AXUIElementCopyActionNames(el, &names)
            return (names as? [String]) ?? []
        }()
        if clickableRoles.contains(role) || actions.contains(kAXPressAction) {
            let f = frame(of: el)
            // Skip zero-size or off-screen elements; they can't be clicked anyway.
            if let f = f, f.width > 0, f.height > 0 {
                counter += 1
                out.append(Element(id: counter, ref: el, role: role, label: label(of: el), frame: f))
            }
        }
        for child in children(of: el) { walk(child, depth: depth + 1, maxDepth: maxDepth) }
    }
    // Top-level menu bar items first (closed menus are skipped; they hold hundreds of items),
    // then windows, so ids are stable.
    if let menuBar: AXUIElement = attr(app, kAXMenuBarAttribute) { walk(menuBar, depth: 0, maxDepth: 2) }
    let windows: [AXUIElement] = attr(app, kAXWindowsAttribute) ?? []
    for w in windows { walk(w, depth: 0) }
    if Date() >= deadline || seen >= maxNodes {
        FileHandle.standardError.write("note: UI tree truncated after \(seen) nodes\n".data(using: .utf8)!)
    }
    return out
}

func runningApp(_ name: String) -> NSRunningApplication? {
    if name == "front" { return NSWorkspace.shared.frontmostApplication }
    let apps = NSWorkspace.shared.runningApplications
    return apps.first { $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame }
        ?? apps.first { $0.localizedName?.localizedCaseInsensitiveContains(name) == true }
}

func clickAt(_ p: CGPoint) {
    let src = CGEventSource(stateID: .hidSystemState)
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(30_000)
    }
}

func press(_ e: Element) {
    if AXUIElementPerformAction(e.ref, kAXPressAction as CFString) == .success {
        print("pressed #\(e.id) \(e.role) \"\(e.label)\" via AXPress")
    } else if let f = e.frame {
        clickAt(CGPoint(x: f.midX, y: f.midY))
        print("clicked #\(e.id) \(e.role) \"\(e.label)\" at \(Int(f.midX)),\(Int(f.midY))")
    } else {
        fail("element #\(e.id) has no press action or frame")
    }
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func describe(_ e: Element) -> String {
    let f = e.frame.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "-"
    return "#\(e.id)\t\(e.role.replacingOccurrences(of: "AX", with: ""))\t\"\(e.label.prefix(80))\"\t\(f)"
}

// MARK: - CLI

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fail("usage: axclick check | list [app] [filter] | press [app] <id> | find [app] <text>")
}
args.removeFirst()

guard AXIsProcessTrusted() else {
    fail("Accessibility access not granted. Enable it in System Settings > Privacy & Security > Accessibility for the app running this command.")
}
if command == "check" { print("ok"); exit(0) }

// The last argument is the id/text for press/find; anything before it is the app name.
let appName: String
let operand: String?
switch command {
case "list":
    appName = args.first ?? "front"
    operand = args.count > 1 ? args[1...].joined(separator: " ") : nil
case "press", "find":
    guard let last = args.last else { fail("\(command) needs an argument") }
    operand = last
    appName = args.count > 1 ? args.dropLast().joined(separator: " ") : "front"
default:
    fail("unknown command \(command)")
}

guard let app = runningApp(appName) else { fail("app not running: \(appName)") }
let axApp = AXUIElementCreateApplication(app.processIdentifier)
// Default is 6s per call; a busy app would otherwise stall the whole walk.
AXUIElementSetMessagingTimeout(axApp, 0.5)
// Chromium and Electron apps only build their accessibility tree when asked to. Electron accepts
// AXManualAccessibility; Chrome 157 and later need AXEnhancedUserInterface, and take about two
// seconds to expose the page after it's first turned on.
let manualAX = AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
var enhancedAX: CFTypeRef?
let wasEnhanced = AXUIElementCopyAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, &enhancedAX) == .success
    && (enhancedAX as? Bool) == true
AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
if manualAX == .attributeUnsupported && !wasEnhanced { Thread.sleep(forTimeInterval: 2.5) }

let elements = collect(app: axApp)

switch command {
case "list":
    let filter = operand?.lowercased()
    print("\(app.localizedName ?? appName): \(elements.count) clickable elements")
    for e in elements where filter == nil || e.label.lowercased().contains(filter!) || e.role.lowercased().contains(filter!) {
        print(describe(e))
    }
case "press":
    guard let id = Int(operand!), let e = elements.first(where: { $0.id == id }) else {
        fail("no element #\(operand!) (run list again; ids change when the UI changes)")
    }
    press(e)
default: // find
    let needle = operand!.lowercased()
    let matches = elements.filter { $0.label.lowercased().contains(needle) }
    guard let e = matches.first(where: { $0.label.lowercased() == needle }) ?? matches.first else {
        fail("no element labelled \"\(operand!)\"")
    }
    press(e)
}
