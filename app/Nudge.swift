// The gentle reminder in official downloads: after 100 uses, and at most once a week, a small
// notice suggesting a license. It appears after a click has landed and never takes focus.
//
// Only official download builds include it: build.sh compiles it in when AXCLICK_OFFICIAL=1.
// Homebrew installs and builds from source never show it.

import AppKit

enum Nudge {
    static let usesBetween = 100
    static let minimumInterval: TimeInterval = 7 * 24 * 60 * 60

    /// Counts one use: labels, scroll mode or grid mode opened.
    static func recordUse() {
        #if OFFICIAL
        let d = UserDefaults.standard
        d.set(d.integer(forKey: "nudgeUses") + 1, forKey: "nudgeUses")
        #endif
    }

    /// Shows the reminder if 100 uses have passed and it hasn't shown in the last week.
    static func showIfDue() {
        #if OFFICIAL
        guard !License.isActive else { return }
        let d = UserDefaults.standard
        guard d.integer(forKey: "nudgeUses") >= usesBetween else { return }
        if let last = d.object(forKey: "nudgeLastShown") as? Date, Date().timeIntervalSince(last) < minimumInterval { return }
        d.set(0, forKey: "nudgeUses")
        d.set(Date(), forKey: "nudgeLastShown")
        NudgePanel.shared.show()
        #endif
    }
}

#if OFFICIAL
/// A small floating notice in the top-right corner. It's a non-activating panel, so the app
/// you're using keeps focus, and it closes on its own after 15 seconds.
final class NudgePanel: NSObject {
    static let shared = NudgePanel()
    var panel: NSPanel?
    var timer: Timer?

    func show() {
        if panel == nil { build() }
        guard let panel = panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameTopLeftPoint(NSPoint(x: visible.maxX - panel.frame.width - 16, y: visible.maxY - 16))
        panel.orderFrontRegardless()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in self?.close() }
    }

    func build() {
        let buy = NSButton(title: "Buy a license", target: self, action: #selector(buyLicense))
        buy.bezelStyle = .rounded
        buy.keyEquivalent = ""
        let enter = NSButton(title: "Enter License", target: self, action: #selector(enterLicense))
        enter.bezelStyle = .rounded
        let later = NSButton(title: "Not now", target: self, action: #selector(close))
        later.bezelStyle = .rounded
        let buttons = NSStackView(views: [buy, enter, later])
        buttons.spacing = 8
        let text = textLabel("axclick is free to use. A $9.99 license removes this reminder and supports its development.")
        text.preferredMaxLayoutWidth = 300
        let stack = verticalStack([textLabel("Enjoying axclick?", bold: true), text, buttons], spacing: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 130),
                        styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            content.widthAnchor.constraint(equalToConstant: 380),
        ])
        p.contentView = content
        panel = p
    }

    @objc func buyLicense() {
        NSWorkspace.shared.open(License.buyURL)
        close()
    }

    @objc func enterLicense() {
        controller.license.show()
        close()
    }

    @objc func close() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
    }
}
#endif
