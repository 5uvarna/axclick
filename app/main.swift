// axclick: keyboard clicking for macOS.
//
// Press the hotkey (⌘⇧Space by default) and a label appears on every clickable element of
// the front app. Type a label to click that element. Shift + last letter right-clicks,
// ⌘ + last letter ⌘-clicks, Backspace removes a letter, Esc (or the hotkey again) cancels.
//
// Elements come from the Accessibility API, so clicks land on the element itself
// (AXPress), or on its exact center when an element has no press action.

import AppKit

let controller = Controller()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// A menu bar app shows no main menu, but standard shortcuts in our windows still go through it.
let mainMenu = NSMenu()
let appMenuItem = mainMenu.addItem(withTitle: "axclick", action: nil, keyEquivalent: "")
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
appMenu.addItem(withTitle: "Quit axclick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appMenuItem.submenu = appMenu
app.mainMenu = mainMenu

controller.setup()
app.run()
