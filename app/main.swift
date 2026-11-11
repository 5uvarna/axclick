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
controller.setup()
app.run()
