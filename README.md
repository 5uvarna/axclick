# axclick

**Click anything on your Mac with the keyboard.** A free, open-source Homerow alternative.

**Website:** [5uvarna.github.io/axclick](https://5uvarna.github.io/axclick/)

Press **⌘⇧Space** and a short label appears on every button, link, menu and field in the app in front. Type a label and axclick clicks it, precisely, through the macOS Accessibility API instead of guessing at screen coordinates.

```
⌘⇧Space  →  labels appear  →  type "SD"  →  clicked
```

## Features

- **Precise clicks.** Elements come from the Accessibility API, so axclick presses the element itself, or clicks its exact center when an element has no press action.
- **Home-row labels.** Labels start with `A S D F J K L`, so the common ones are quick to type.
- **Keeps your focus.** The app in front stays active while labels are showing, so open menus and popovers stay open.
- **Works in most apps**, including Chrome, Electron apps like VS Code, Finder, menus and dialogs.
- **Menu bar icons too.** Wi-Fi, Bluetooth, sound, battery, Control Center and other apps' menu bar icons get labels.
- **Grid mode** for anything without labels (games, canvases, remote desktops). Press `Space` while labels show, then press three keys on the `Q W E R` / `A S D F` / `Z X C V` grid to click anywhere.
- **Search by text.** Press `/` and type the words on a button or link, like "save" or "sign in", instead of its label.
- **Scroll mode.** Press **⌘⇧J** and scroll the window with `j` `k` `h` `l`, half a page with `d` `u`, or jump to the top or bottom with `g` `G`.
- **Right-click and ⌘-click** from the keyboard.
- **Your own shortcuts.** Change both shortcuts in Settings, and turn on launch at login.
- **A command-line tool** for scripts and automation.
- **Small and dependency-free.** Plain Swift with no frameworks beyond what macOS ships.

## Keys

### Labels

| Key | Action |
|---|---|
| `⌘⇧Space` | Show labels (press again to cancel). Change it in Settings |
| Type a label | Click that element |
| `Shift` + last letter | Right-click |
| `⌘` + last letter | ⌘-click (e.g. open a link in a new tab) |
| `Backspace` | Remove the last typed letter |
| `/` | Search by text instead |
| `Space` | Grid mode instead |
| `Esc` | Cancel |

### Search (after `/`)

| Key | Action |
|---|---|
| Type text | Keep only elements whose text matches. Exact matches come first |
| `Return` | Click the selected match (`Shift`+`Return` right-clicks, `⌘`+`Return` ⌘-clicks) |
| `Tab` / `↓` | Next match (`Shift`+`Tab` / `↑` for the previous one) |
| `Backspace` | Delete a letter, or go back to labels when the search is empty |
| `Esc` | Cancel |

### Grid mode (after `Space`, or from the menu bar icon)

The screen with the pointer splits into a 4×3 grid, each cell named after the key in the same spot under your left hand: `Q W E R` on top, `A S D F` in the middle, `Z X C V` at the bottom. Press one to zoom into that cell, which splits the same way again. A red dot marks where a click will land. Once a cell is smaller than 45 points, axclick clicks it right away: that's the third key on a laptop or 1080p screen, the fourth on larger displays. Grid mode also appears on its own when an app has nothing to label.

| Key | Action |
|---|---|
| `Q` `W` `E` `R` / `A` `S` `D` `F` / `Z` `X` `C` `V` | Zoom into that cell (the last key clicks; hold `Shift` to right-click, `⌘` to ⌘-click) |
| `Return` / `Space` | Click the red dot now, without zooming further |
| `Backspace` | Zoom back out |
| `1`–`9` | Switch to another screen |
| `Esc` | Cancel |

### Scroll mode

| Key | Action |
|---|---|
| `⌘⇧J` | Start scroll mode (press again to stop). Change it in Settings |
| `j` `k` / `↓` `↑` | Scroll down / up (hold `Shift` for faster) |
| `h` `l` / `←` `→` | Scroll left / right |
| `d` `u` | Half a page down / up |
| `g` `G` | Jump to the top / bottom |
| `1`–`9`, `Tab` | Pick another scrollable area when there are several (the selected one is outlined in blue) |
| `Esc` | Stop |

## Install

### Homebrew (free, builds from source)

```bash
brew install 5uvarna/tap/axclick
```

If Homebrew asks you to trust the tap first, run `brew trust --formula 5uvarna/tap/axclick` and try again. Homebrew builds axclick on your Mac, so it needs up-to-date Xcode or Command Line Tools. Then start it with `open $(brew --prefix axclick)/axclick.app`.

Homebrew builds are signed ad hoc, so after each `brew upgrade axclick` turn axclick off and on again in Accessibility settings.

### Ready-to-run download (coming soon)

A signed, notarized download for people who'd rather not use developer tools. It's free, with a small reminder after every 100 uses, at most once a week. It never interrupts a click and never steals focus. A $9.99 one-time license removes it. Homebrew and source builds never show the reminder.

### Build it yourself (free)

Needs the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/5uvarna/axclick.git
cd axclick
./build.sh install
```

This builds the app, installs it to `~/Applications/axclick.app` and starts it. An axe icon appears in the menu bar.

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

Click the axe icon in the menu bar and choose **Settings…** to:

- **Change the shortcuts** for labels and scroll mode. Click a shortcut button and type a new one: two modifiers with a key (like ⌘⇧Space), or one modifier with Space or a function key. Shortcuts like ⌘W are refused, so you can't accidentally take over an everyday app shortcut.
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

1. Carbon hotkeys listen for ⌘⇧Space and ⌘⇧J.
2. axclick walks the front app's accessibility tree: the menu bar, any open menu, the focused window and any popovers or sheets. At the same time it reads the menu bar icons of the apps that have them. Subtrees scrolled out of view are skipped, and the walk stops after 1.5 seconds, so labels appear in about half a second.
3. Labels are drawn in a transparent, click-through overlay window on each screen.
4. While labels are showing, a keyboard event tap takes your keystrokes, so the app in front keeps focus without receiving them.
5. When a label is complete, axclick calls `AXPress` on the element. For text fields, cells and elements without a press action, it posts a real click at the element's center.
6. Search reads each element's title, description, placeholder or inner text in the background while labels show.
7. Scroll mode finds the scroll areas in the focused window and posts scroll events at the selected one without moving the pointer. Top and bottom set the area's scroll bar directly when the app exposes one.

## Limitations

- Apps that don't expose accessibility info (some games, some custom-drawn UIs) show few or no labels.
- Very large pages may be cut off by the 1.5-second walk limit.
- axclick's shortcuts work in every app, so they take over any app shortcut that uses the same keys. If one clashes with an app you use, change it in Settings.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Contributions come with license terms that let the maintainer keep distributing official builds.

## License

[GNU GPL v3](LICENSE). You're free to use, study, change and share axclick. If you distribute a modified version, you have to share its source under the same license.
