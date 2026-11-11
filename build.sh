#!/bin/bash
# Builds the axclick menu bar app and command-line tool.
#   ./build.sh            build into build/
#   ./build.sh install    also install the app to ~/Applications and restart it
# Each rebuild changes the ad-hoc signature, so macOS asks for Accessibility access again.
set -euo pipefail
cd "$(dirname "$0")"

app=build/axclick.app
rm -rf build
mkdir -p "$app/Contents/MacOS"
swiftc -O app/main.swift -o "$app/Contents/MacOS/axclick"
swiftc -O cli/main.swift -o build/axclick

cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.5uvarna.axclick</string>
  <key>CFBundleName</key><string>axclick</string>
  <key>CFBundleExecutable</key><string>axclick</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - --identifier io.github.5uvarna.axclick "$app"
codesign --force --sign - build/axclick
echo "built $app and build/axclick"

if [ "${1:-}" = install ]; then
    pkill -f "axclick.app/Contents/MacOS/axclick" || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/axclick.app
    cp -R "$app" ~/Applications/
    open ~/Applications/axclick.app
    echo "installed and started ~/Applications/axclick.app"
fi
