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

    static let `default` = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "Space")

    static var saved: HotKey {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: "hotKeyCode") != nil, let label = d.string(forKey: "hotKeyLabel") else { return .default }
            return HotKey(keyCode: UInt32(d.integer(forKey: "hotKeyCode")),
                          modifiers: UInt32(d.integer(forKey: "hotKeyModifiers")), keyLabel: label)
        }
        set {
            let d = UserDefaults.standard
            d.set(Int(newValue.keyCode), forKey: "hotKeyCode")
            d.set(Int(newValue.modifiers), forKey: "hotKeyModifiers")
            d.set(newValue.keyLabel, forKey: "hotKeyLabel")
        }
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// A shortcut typed in the recorder; nil without ⌘, ⌥ or ⌃, since it would fire while typing.
    init?(event: NSEvent) {
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard f.contains(.command) || f.contains(.option) || f.contains(.control) else { return nil }
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
    let shortcutButton = NSButton(title: "", target: nil, action: nil)
    let loginCheckbox = NSButton(checkboxWithTitle: "Launch axclick at login", target: nil, action: nil)
    let message = textLabel("", size: 11, color: .secondaryLabelColor)
    var monitor: Any?

    func show() {
        if window == nil { build() }
        refresh()
        bringToFront(window)
    }

    func build() {
        shortcutButton.target = self
        shortcutButton.action = #selector(record)
        shortcutButton.bezelStyle = .rounded
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        let row = NSStackView(views: [textLabel("Show hints:"), shortcutButton])
        row.spacing = 8
        let stack = verticalStack([
            row, message, loginCheckbox,
            textLabel("axclick \(appVersion) · GPL-3.0 · github.com/5uvarna/axclick", size: 11, color: .secondaryLabelColor),
        ])
        window = makeWindow(title: "axclick Settings", content: stack)
        window?.delegate = self
    }

    // Leaving the window mid-recording would otherwise leave the hotkey unregistered.
    func windowDidResignKey(_ notification: Notification) {
        if monitor != nil { finish("") }
    }

    func refresh() {
        shortcutButton.title = HotKey.saved.description
        loginCheckbox.state = LoginItem.enabled ? .on : .off
    }

    @objc func record() {
        guard monitor == nil else { return }
        shortcutButton.title = "Type a shortcut…"
        message.stringValue = "Use ⌘, ⌥ or ⌃ with a key. Esc cancels."
        controller.unregisterHotKey() // so pressing the current shortcut records it instead of firing
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.capture(event)
            return nil
        }
    }

    func capture(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { finish(""); return }
        guard let hotKey = HotKey(event: event) else { NSSound.beep(); return }
        let previous = HotKey.saved
        HotKey.saved = hotKey
        if controller.registerHotKey() {
            finish("")
        } else {
            HotKey.saved = previous
            finish("\(hotKey.description) is already used by another app. Try another.")
        }
    }

    func finish(_ note: String) {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        controller.registerHotKey()
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
        let hotKey = HotKey.saved.description
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
            textLabel("Press \(hotKey) in any app and a label appears on every button, link and menu. Type a label to click it."),
            textLabel("To find and press those elements, axclick needs Accessibility access. It only looks at the app in front, only while labels are showing, and never sends anything over the network."),
            textLabel("In System Settings, turn on axclick in the list. If it isn't there, click + and add it from your Applications folder.",
                      color: .secondaryLabelColor),
            openButton, status, loginCheckbox, doneButton,
        ])
        window = makeWindow(title: "Welcome to axclick", content: stack)
    }

    func update() {
        let hotKey = HotKey.saved.description
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
