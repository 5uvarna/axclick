// The hotkey setting, launch at login, the settings window and the first-run welcome window.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

// MARK: - Hotkey

struct HotKey: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon mask: cmdKey, shiftKey, optionKey, controlKey
    var keyLabel: String

    /// What a shortcut does. Each has its own saved shortcut and Carbon hotkey id.
    enum Action: UInt32, CaseIterable {
        case hints = 1, scroll = 2

        var title: String { self == .hints ? "Show hints" : "Scroll mode" }
        var defaultsPrefix: String { self == .hints ? "hotKey" : "scrollHotKey" }
        var defaultHotKey: HotKey {
            self == .hints
                ? HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "Space")
                : HotKey(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "J")
        }
    }

    static func saved(_ action: Action) -> HotKey {
        let d = UserDefaults.standard, p = action.defaultsPrefix
        guard d.object(forKey: p + "Code") != nil, let label = d.string(forKey: p + "Label") else { return action.defaultHotKey }
        return HotKey(keyCode: UInt32(d.integer(forKey: p + "Code")),
                      modifiers: UInt32(d.integer(forKey: p + "Modifiers")), keyLabel: label)
    }

    static func save(_ hotKey: HotKey, for action: Action) {
        let d = UserDefaults.standard, p = action.defaultsPrefix
        d.set(Int(hotKey.keyCode), forKey: p + "Code")
        d.set(Int(hotKey.modifiers), forKey: p + "Modifiers")
        d.set(hotKey.keyLabel, forKey: p + "Label")
    }

    /// Whether a key event from the event tap is this shortcut.
    func matches(keyCode: Int, flags: CGEventFlags) -> Bool {
        keyCode == Int(self.keyCode)
            && flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]) == cgFlags
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// A shortcut typed in the recorder. Rejects shortcuts that would steal everyday keys:
    /// plain keys and ⇧-keys fire while typing, and one modifier with a letter (⌘W, ⌃C) is
    /// usually an app shortcut. One modifier is fine with Space or a function key.
    init?(event: NSEvent) {
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard f.contains(.command) || f.contains(.option) || f.contains(.control) else { return nil }
        let count = [f.contains(.command), f.contains(.shift), f.contains(.option), f.contains(.control)].filter { $0 }.count
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        guard count >= 2 || Int(event.keyCode) == kVK_Space || functionKeys.contains(Int(event.keyCode)) else { return nil }
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        let named: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        let label = named[Int(event.keyCode)] ?? event.characters(byApplyingModifiers: [])?.uppercased() ?? "?"
        self.init(keyCode: UInt32(event.keyCode), modifiers: m, keyLabel: label)
    }

    /// The same modifiers as event-tap flags, for spotting the hotkey while hints are showing.
    var cgFlags: CGEventFlags {
        var f: CGEventFlags = []
        if modifiers & UInt32(cmdKey) != 0 { f.insert(.maskCommand) }
        if modifiers & UInt32(shiftKey) != 0 { f.insert(.maskShift) }
        if modifiers & UInt32(optionKey) != 0 { f.insert(.maskAlternate) }
        if modifiers & UInt32(controlKey) != 0 { f.insert(.maskControl) }
        return f
    }

    var description: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyLabel
    }
}

// MARK: - Launch at login

enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("axclick: launch at login change failed: \(error)")
        }
        // macOS can hold a new login item until the user approves it in System Settings.
        if on && SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}

// MARK: - Window helpers

func textLabel(_ s: String, size: CGFloat = 13, bold: Bool = false, color: NSColor = .labelColor) -> NSTextField {
    let l = NSTextField(wrappingLabelWithString: s)
    l.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
    l.textColor = color
    l.preferredMaxLayoutWidth = 372
    return l
}

func makeWindow(title: String, content: NSView) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = title
    window.isReleasedWhenClosed = false
    let container = NSView()
    content.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(content)
    NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
        content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
        content.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
        content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
        container.widthAnchor.constraint(equalToConstant: 420),
    ])
    window.contentView = container
    window.center()
    return window
}

func bringToFront(_ window: NSWindow?) {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
}

func verticalStack(_ views: [NSView], spacing: CGFloat = 14) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = spacing
    return stack
}

// MARK: - Settings window

final class SettingsWindowController: NSObject, NSWindowDelegate {
    var window: NSWindow?
    var buttons: [HotKey.Action: NSButton] = [:]
    let loginCheckbox = NSButton(checkboxWithTitle: "Launch axclick at login", target: nil, action: nil)
    let message = textLabel("", size: 11, color: .secondaryLabelColor)
    var monitor: Any?
    var recording: HotKey.Action?

    func show() {
        if window == nil { build() }
        refresh()
        bringToFront(window)
    }

    func build() {
        var rows: [NSView] = []
        for action in HotKey.Action.allCases {
            let button = NSButton(title: "", target: self, action: #selector(record(_:)))
            button.bezelStyle = .rounded
            button.tag = Int(action.rawValue)
            buttons[action] = button
            let label = textLabel(action.title + ":")
            label.widthAnchor.constraint(equalToConstant: 96).isActive = true
            let row = NSStackView(views: [label, button])
            row.spacing = 8
            rows.append(row)
        }
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        let stack = verticalStack(rows + [
            message, loginCheckbox,
            textLabel("axclick \(appVersion) · GPL-3.0 · github.com/5uvarna/axclick", size: 11, color: .secondaryLabelColor),
        ])
        window = makeWindow(title: "axclick Settings", content: stack)
        window?.delegate = self
    }

    // Leaving the window mid-recording would otherwise leave the hotkeys unregistered.
    func windowDidResignKey(_ notification: Notification) {
        if monitor != nil { finish("") }
    }

    func refresh() {
        for (action, button) in buttons {
            button.title = action == recording ? "Type a shortcut…" : HotKey.saved(action).description
        }
        loginCheckbox.state = LoginItem.enabled ? .on : .off
    }

    @objc func record(_ sender: NSButton) {
        guard monitor == nil, let action = HotKey.Action(rawValue: UInt32(sender.tag)) else { return }
        recording = action
        refresh()
        message.stringValue = "Use two modifiers with a key (like ⌘⇧Space), or one with Space. Esc cancels."
        controller.unregisterHotKeys() // so pressing a current shortcut records it instead of firing
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.capture(event)
            return nil
        }
    }

    func capture(_ event: NSEvent) {
        guard let action = recording else { return }
        if event.keyCode == UInt16(kVK_Escape) { finish(""); return }
        guard let hotKey = HotKey(event: event) else { NSSound.beep(); return }
        if let other = HotKey.Action.allCases.first(where: { $0 != action && HotKey.saved($0) == hotKey }) {
            finish("\(hotKey.description) is already the \(other.title.lowercased()) shortcut.")
            return
        }
        let previous = HotKey.saved(action)
        HotKey.save(hotKey, for: action)
        if controller.registerHotKey(action) {
            finish("")
        } else {
            HotKey.save(previous, for: action)
            finish("\(hotKey.description) is already used by another app. Try another.")
        }
    }

    func finish(_ note: String) {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = nil
        controller.registerHotKeys()
        message.stringValue = note
        refresh()
    }

    @objc func toggleLogin() {
        LoginItem.set(loginCheckbox.state == .on)
        refresh()
    }
}

// MARK: - Welcome window

/// Shown when axclick lacks Accessibility access: explains why it needs it and waits for it.
final class WelcomeWindowController: NSObject {
    var window: NSWindow?
    var timer: Timer?
    let status = textLabel("")
    let doneButton = NSButton(title: "Done", target: nil, action: nil)
    let loginCheckbox = NSButton(checkboxWithTitle: "Launch axclick at login", target: nil, action: nil)

    func show() {
        if window == nil { build() }
        loginCheckbox.state = LoginItem.enabled ? .on : .off
        update()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
        bringToFront(window)
    }

    func build() {
        let hotKey = HotKey.saved(.hints).description
        let openButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openSettings))
        openButton.bezelStyle = .rounded
        openButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(done)
        doneButton.bezelStyle = .rounded
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        let stack = verticalStack([
            textLabel("Welcome to axclick", size: 18, bold: true),
            textLabel("Press \(hotKey) in any app and a label appears on every button, link and menu. Type a label to click it, or press / and type its text. \(HotKey.saved(.scroll).description) scrolls with the keyboard."),
            textLabel("To find and press those elements, axclick needs Accessibility access. It only looks at the app in front, only while labels are showing, and never sends anything over the network."),
            textLabel("In System Settings, turn on axclick in the list. If it isn't there, click + and add it from your Applications folder.",
                      color: .secondaryLabelColor),
            openButton, status, loginCheckbox, doneButton,
        ])
        window = makeWindow(title: "Welcome to axclick", content: stack)
    }

    func update() {
        let hotKey = HotKey.saved(.hints).description
        if AXIsProcessTrusted() {
            status.stringValue = "✅ Access granted. Press \(hotKey) in any app to try it."
            doneButton.isEnabled = true
        } else {
            status.stringValue = "Waiting for Accessibility access…"
            doneButton.isEnabled = false
        }
    }

    @objc func openSettings() {
        // Asking with the prompt option adds axclick to the Accessibility list.
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func toggleLogin() {
        LoginItem.set(loginCheckbox.state == .on)
        loginCheckbox.state = LoginItem.enabled ? .on : .off
    }

    @objc func done() {
        timer?.invalidate()
        timer = nil
        window?.close()
    }
}
