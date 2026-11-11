# axclick

**Click anything on your Mac with the keyboard.** A free, open-source Homerow alternative.

Press **⌘⇧Space** and a short label appears on every button, link, menu and field in the app in front. Type a label and axclick clicks it, precisely, through the macOS Accessibility API instead of guessing at screen coordinates.

```
⌘⇧Space  →  labels appear  →  type "SD"  →  clicked
```

## Features

- **Precise clicks.** Elements come from the Accessibility API, so axclick presses the element itself, or clicks its exact center when an element has no press action.
- **Home-row labels.** Labels start with `A S D F J K L`, so the common ones are quick to type.
- **Keeps your focus.** The app in front stays active while labels are showing, so open menus and popovers stay open.
- **Works in most apps**, including Chrome, Electron apps like VS Code, Finder, menus and dialogs.
- **Right-click and ⌘-click** from the keyboard.
- **Your own shortcut.** Change the hotkey in Settings, and turn on launch at login.
- **A command-line tool** for scripts and automation.
- **Small and dependency-free.** Plain Swift with no frameworks beyond what macOS ships.

## Keys

| Key | Action |
|---|---|
| `⌘⇧Space` | Show labels (press again to cancel). Change it in Settings |
| Type a label | Click that element |
| `Shift` + last letter | Right-click |
| `⌘` + last letter | ⌘-click (e.g. open a link in a new tab) |
| `Backspace` | Remove the last typed letter |
| `Esc` | Cancel |

## Install

### Build it yourself (free)

Needs the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/5uvarna/axclick.git
cd axclick
./build.sh install
```

This builds the app, installs it to `~/Applications/axclick.app` and starts it. A keyboard icon appears in the menu bar.

### Grant Accessibility access

On first launch, axclick opens a welcome window that explains why it needs Accessibility access and opens the right page in System Settings. Turn on **axclick** there and the window confirms when access is granted.

axclick only reads the app in front, only while labels are showing, and makes no network connections.

### Keep access across rebuilds (optional)

By default your builds are signed ad hoc, so macOS treats each rebuild as a new app and you have to grant Accessibility access again. If you rebuild often, run this once:

```bash
./scripts/setup-signing.sh
```

It creates a self-signed certificate named "axclick Local Signing" in your login keychain, and `build.sh` signs with it from then on. Grant access one more time after the next build, and it sticks from then on. The certificate only signs your own local builds.

## Settings

Click the keyboard icon in the menu bar and choose **Settings…** to:

- **Change the shortcut.** Click the shortcut button and type a new one. It needs ⌘, ⌥ or ⌃.
- **Launch at login.**

## Command-line tool

`./build.sh` also builds `build/axclick`, the same element finding as a CLI. Copy it somewhere on your `PATH` to use it anywhere.

```bash
axclick list "Google Chrome"            # every clickable element: id, role, label, frame
axclick list "Google Chrome" sign       # filter by label or role
axclick find "Google Chrome" "Sign in"  # press the element with that label
axclick press "Google Chrome" 35        # press by id from `list`
axclick check                           # exits 0 if Accessibility access is granted
```

Leave out the app name to use the frontmost app. Ids change when the UI changes, so run `list` again before `press`. The terminal app you run it from needs Accessibility access too.

## How it works

1. A Carbon hotkey listens for ⌘⇧Space.
2. axclick walks the front app's accessibility tree: the menu bar, any open menu, the focused window and any popovers or sheets. Subtrees scrolled out of view are skipped, and the walk stops after 1.5 seconds, so labels appear in about half a second.
3. Labels are drawn in a transparent, click-through overlay window on each screen.
4. While labels are showing, a keyboard event tap takes your keystrokes, so the app in front keeps focus without receiving them.
5. When a label is complete, axclick calls `AXPress` on the element. For text fields, cells and elements without a press action, it posts a real click at the element's center.

## Limitations

- Apps that don't expose accessibility info (some games, some custom-drawn UIs) show few or no labels.
- Very large pages may be cut off by the 1.5-second walk limit.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Contributions come with license terms that let the maintainer keep distributing official builds.

## License

[GNU GPL v3](LICENSE). You're free to use, study, change and share axclick. If you distribute a modified version, you have to share its source under the same license.
