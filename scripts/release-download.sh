#!/bin/bash
# Builds the official ready-to-run download: the app with the license reminder and Gumroad
# license keys (AXCLICK_OFFICIAL=1), signed with the "axclick Local Signing" certificate from
# scripts/setup-signing.sh, zipped as dist/axclick.zip.
#
#   scripts/release-download.sh            build and check dist/axclick.zip
#   scripts/release-download.sh --upload   also attach it to the GitHub release for this version
#
# Every download must be signed with the same certificate. macOS ties a user's Accessibility
# permission to it, so a download signed any other way (or ad hoc) makes everyone grant access
# again. Keep a backup of the certificate (Keychain Access → export "axclick Local Signing").
#
# Without an Apple Developer ID the app isn't notarized, so on first launch macOS asks people to
# allow it in System Settings → Privacy & Security → Open Anyway. The website explains this.
set -euo pipefail
cd "$(dirname "$0")/.."

identity="axclick Local Signing"
if ! security find-certificate -c "$identity" >/dev/null 2>&1; then
    echo "error: the \"$identity\" certificate isn't in your keychain. Run scripts/setup-signing.sh," >&2
    echo "or restore your backup of it. Downloads must always be signed with the same certificate." >&2
    exit 1
fi

version=$(sed -n 's|.*<key>CFBundleShortVersionString</key><string>\(.*\)</string>.*|\1|p' build.sh)
echo "building axclick $version (official download)"
AXCLICK_OFFICIAL=1 ./build.sh

app=build/axclick.app
codesign --verify --strict "$app"
if codesign -dv "$app" 2>&1 | grep -q "Signature=adhoc"; then
    echo "error: the app was signed ad hoc, not with \"$identity\"" >&2
    exit 1
fi
if ! strings -a "$app/Contents/MacOS/axclick" | grep -q "api.gumroad.com"; then
    echo "error: this build has no license check (is gumroadProductID set in app/License.swift?)" >&2
    exit 1
fi

mkdir -p dist
rm -f dist/axclick.zip
# ditto keeps the signature and permissions intact; zip can break them.
ditto -c -k --keepParent "$app" dist/axclick.zip
echo "wrote dist/axclick.zip ($(du -h dist/axclick.zip | cut -f1), axclick $version, signed with \"$identity\")"

if [ "${1:-}" = --upload ]; then
    gh release upload "v$version" dist/axclick.zip --clobber --repo 5uvarna/axclick
    echo "attached to https://github.com/5uvarna/axclick/releases/tag/v$version"
    echo "latest download link: https://github.com/5uvarna/axclick/releases/latest/download/axclick.zip"
fi
