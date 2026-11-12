#!/bin/bash
# Installs or updates axclick, the ready-to-run download.
#
#   curl -fsSL https://5uvarna.github.io/axclick/install.sh | bash
#
# What it does, step by step:
#   1. downloads the latest axclick.zip from github.com/5uvarna/axclick/releases
#   2. checks the app is signed with axclick's certificate, and stops if it isn't
#   3. quits axclick if it's running, puts the new copy in /Applications
#      (or ~/Applications if you can't write to /Applications), and opens it
#
# Files downloaded with curl aren't marked as "downloaded from the internet", so macOS opens
# the app without the "Not Opened" dialog. Read this script before running it if you like:
# it's short, and it changes nothing outside the axclick app.
set -euo pipefail

url="https://github.com/5uvarna/axclick/releases/latest/download/axclick.zip"
# The signature every official axclick download has: this app id, signed by this certificate.
requirement='identifier "io.github.5uvarna.axclick" and certificate leaf = H"634c429b515f7d65efe672b9e0fbaf2f137753bd"'

if [ "$(uname -s)" != Darwin ]; then
    echo "axclick only runs on macOS." >&2
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading axclick…"
curl -fsSL "$url" -o "$tmp/axclick.zip"
ditto -x -k "$tmp/axclick.zip" "$tmp/unzipped"
app=$(find "$tmp/unzipped" -maxdepth 2 -name axclick.app -type d | head -1)
if [ -z "$app" ]; then
    echo "The download didn't contain axclick.app. Nothing was installed." >&2
    exit 1
fi

echo "Checking the signature…"
if ! codesign --verify --strict -R="$requirement" "$app" 2>/dev/null; then
    echo "This copy of axclick isn't signed with axclick's certificate. Nothing was installed." >&2
    echo "Please report it at https://github.com/5uvarna/axclick/issues" >&2
    exit 1
fi

dest=/Applications
[ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }

# Quit a running copy so it can be replaced.
osascript -e 'tell application id "io.github.5uvarna.axclick" to quit' >/dev/null 2>&1 || true
pkill -f "axclick.app/Contents/MacOS/axclick" 2>/dev/null || true
sleep 1

rm -rf "$dest/axclick.app"
ditto "$app" "$dest/axclick.app"
version=$(defaults read "$dest/axclick.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "")
echo "Installed axclick $version in $dest."

open "$dest/axclick.app"
echo "axclick is running: look for the axe icon in your menu bar."
echo "If this is your first install, it will ask for Accessibility access. Press ⌘⇧Space to start."
