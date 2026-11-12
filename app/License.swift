// Gumroad license keys for official downloads: the "Enter License…" window, one check with
// Gumroad when a key is entered, and the key kept in the Keychain so the reminder stays off.
//
// Only official builds include this (build.sh with AXCLICK_OFFICIAL=1). Homebrew and source
// builds contain no networking code at all.

import AppKit
import Security

enum License {
    /// Set this to the product ID from Gumroad (product settings → the "product_id" for the
    /// license API) before the first official build.
    static let gumroadProductID = "NjQ_KnwCuIMv7sQB_bDEww=="
    /// The product page where people buy a license.
    static let buyURL = URL(string: "https://ash19x.gumroad.com/l/qvpxln")!
    /// Each check counts one use on Gumroad, so this caps how many Macs one key unlocks.
    /// Gumroad can't tell machines apart, so a reinstall also counts; people over the limit
    /// can email for a reset.
    static let maxActivations = 5

    #if OFFICIAL
    static var isActive: Bool { savedKey() != nil }
    #else
    static var isActive: Bool { false }
    #endif
}

#if OFFICIAL

// MARK: - Checking a key with Gumroad

extension License {
    enum CheckResult {
        case valid
        case invalid(String) // a message to show
    }

    /// Asks Gumroad whether a key belongs to axclick and wasn't refunded or charged back.
    /// The only network request axclick makes, and only when someone enters a key.
    static func check(_ key: String, completion: @escaping (CheckResult) -> Void) {
        guard !gumroadProductID.isEmpty else {
            completion(.invalid("Licenses aren't set up in this build yet."))
            return
        }
        var request = URLRequest(url: URL(string: "https://api.gumroad.com/v2/licenses/verify")!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = ["product_id": gumroadProductID, "license_key": key, "increment_uses_count": "true"]
        request.httpBody = form.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
        }.joined(separator: "&").data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, error in
            let result: CheckResult
            if error != nil || data == nil {
                result = .invalid("Couldn't reach Gumroad. Check your internet connection and try again.")
            } else {
                result = interpret(data!)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// Reads Gumroad's answer. Gumroad itself rejects keys for other products, disabled keys
    /// and expired access, but a refunded or charged-back sale still comes back as a success,
    /// so those flags are checked here. Nothing else from the response (the buyer's name,
    /// email or address) is kept.
    static func interpret(_ data: Data) -> CheckResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .invalid("Gumroad sent an answer axclick didn't understand. Please try again later.")
        }
        guard json["success"] as? Bool == true else {
            let message = json["message"] as? String ?? "That license key isn't valid."
            return .invalid(message == "That license does not exist for the provided product."
                            ? "That license key isn't valid for axclick." : message)
        }
        let purchase = json["purchase"] as? [String: Any] ?? [:]
        func flag(_ name: String) -> Bool { purchase[name] as? Bool == true }
        if flag("refunded") { return .invalid("This license was refunded.") }
        if flag("chargebacked") || (flag("disputed") && !flag("dispute_won")) {
            return .invalid("This license's payment was disputed.")
        }
        if let uses = json["uses"] as? Int, uses > maxActivations {
            return .invalid("This license has been activated \(uses) times, more than the \(maxActivations) allowed. Reply to your Gumroad receipt email to have it reset.")
        }
        return .valid
    }
}

// MARK: - Keychain

extension License {
    private static let service = "io.github.5uvarna.axclick.license"

    static func savedKey() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        remove()
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: "license", kSecValueData as String: Data(key.utf8)]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func remove() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}

// MARK: - The Enter License window

final class LicenseWindowController: NSObject {
    var window: NSWindow?
    let field = NSTextField()
    let status = textLabel("")
    let activateButton = NSButton(title: "Activate", target: nil, action: nil)
    let buyButton = NSButton(title: "Buy a License", target: nil, action: nil)
    let removeButton = NSButton(title: "Remove License", target: nil, action: nil)

    func show() {
        if window == nil { build() }
        refresh()
        bringToFront(window)
    }

    func build() {
        field.placeholderString = "XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX"
        field.widthAnchor.constraint(equalToConstant: 372).isActive = true
        for (button, action) in [(activateButton, #selector(activate)), (buyButton, #selector(buy)), (removeButton, #selector(removeLicense))] {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
        }
        activateButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [activateButton, buyButton, removeButton])
        buttons.spacing = 8
        let stack = verticalStack([
            textLabel("axclick License", size: 18, bold: true),
            textLabel("axclick is free to use. A license removes the reminder and supports development. Paste the key from your Gumroad receipt."),
            field, buttons, status,
            textLabel("Activating checks the key with Gumroad once. axclick makes no other network connections.",
                      size: 11, color: .secondaryLabelColor),
        ])
        window = makeWindow(title: "axclick License", content: stack)
    }

    func refresh() {
        let active = License.isActive
        field.isHidden = active
        activateButton.isHidden = active
        buyButton.isHidden = active
        removeButton.isHidden = !active
        status.stringValue = active ? "✅ Licensed. Thank you for supporting axclick!" : ""
    }

    @objc func activate() {
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { status.stringValue = "Paste your license key first."; return }
        activateButton.isEnabled = false
        status.stringValue = "Checking with Gumroad…"
        License.check(key) { [weak self] result in
            guard let self = self else { return }
            self.activateButton.isEnabled = true
            switch result {
            case .valid:
                if License.save(key) {
                    self.field.stringValue = ""
                    self.refresh()
                } else {
                    self.status.stringValue = "The key is valid, but axclick couldn't save it to your Keychain."
                }
            case .invalid(let message):
                self.status.stringValue = message
            }
        }
    }

    @objc func buy() { NSWorkspace.shared.open(License.buyURL) }

    @objc func removeLicense() {
        // Activating again counts against the key's limit, so make removing it deliberate.
        let alert = NSAlert()
        alert.messageText = "Remove the license from this Mac?"
        alert.informativeText = "The reminder will come back. Activating the key again counts as one of its \(License.maxActivations) activations."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard let window = window else { return }
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            License.remove()
            self.refresh()
        }
    }
}

#endif
