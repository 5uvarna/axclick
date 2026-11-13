#!/bin/bash
# Builds the axclick menu bar app and command-line tool.
#   ./build.sh            build into build/
#   ./build.sh install    also install the app to ~/Applications and restart it
# Run scripts/setup-signing.sh once so rebuilds keep their Accessibility access.
set -euo pipefail
cd "$(dirname "$0")"

app=build/axclick.app
rm -rf build
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# The icon is drawn by app/Logo.swift; regenerate it with scripts/make-icon after changing the logo.
cp app/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# AXCLICK_OFFICIAL=1 is for official download builds only: it adds the license reminder
# (app/Nudge.swift). Homebrew and source builds leave it out.
official=""
if [ "${AXCLICK_OFFICIAL:-}" = 1 ]; then official="-D OFFICIAL"; fi
# Build for both Apple silicon and Intel, for macOS 13 and later (LSMinimumSystemVersion below).
# Without -target, swiftc builds only for this Mac's chip and macOS version.
universal() { # output, then the files to compile
    local out=$1; shift
    swiftc -O $official -target arm64-apple-macos13.0 "$@" -o "$out.arm64"
    swiftc -O $official -target x86_64-apple-macos13.0 "$@" -o "$out.x86_64"
    lipo -create "$out.arm64" "$out.x86_64" -output "$out"
    rm "$out.arm64" "$out.x86_64"
}
universal "$app/Contents/MacOS/axclick" app/*.swift
official="" universal build/axclick cli/main.swift

cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.5uvarna.axclick</string>
  <key>CFBundleName</key><string>axclick</string>
  <key>CFBundleExecutable</key><string>axclick</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3.4</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# Sign with the local certificate from scripts/setup-signing.sh when it exists, so macOS keeps
# the Accessibility permission across rebuilds. Otherwise fall back to an ad-hoc signature.
# AXCLICK_ADHOC=1 forces ad hoc, for package builds (Homebrew) that must not touch a keychain.
identity="-"
if [ "${AXCLICK_ADHOC:-}" != 1 ] && security find-certificate -c "axclick Local Signing" >/dev/null 2>&1; then
    identity="axclick Local Signing"
fi
codesign --force --sign "$identity" --identifier io.github.5uvarna.axclick "$app"
codesign --force --sign "$identity" build/axclick
echo "built $app and build/axclick (signed with: ${identity/#-/ad hoc})"

if [ "${1:-}" = install ]; then
    pkill -f "axclick.app/Contents/MacOS/axclick" || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/axclick.app
    cp -R "$app" ~/Applications/
    open ~/Applications/axclick.app
    echo "installed and started ~/Applications/axclick.app"
fi
