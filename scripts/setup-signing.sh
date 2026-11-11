#!/bin/bash
# One-time setup: creates a self-signed code signing certificate named "axclick Local Signing"
# in your login keychain. build.sh signs with it when it exists.
#
# Why: ad-hoc signatures change on every build, so macOS forgets the Accessibility permission
# after each rebuild. A certificate gives every build the same identity, so the permission sticks.
#
# The certificate only signs your own local builds. It is not trusted for anything else and
# cannot be used to sign apps for other people (that needs an Apple Developer ID).
set -euo pipefail

name="axclick Local Signing"
keychain="$HOME/Library/Keychains/login.keychain-db"

allow_codesign() {
    # Without this, macOS asks before every codesign run and a build waits on the dialog.
    # It asks for your login password once, here in the terminal.
    echo "Allowing codesign to use the key. Enter your Mac login password when asked."
    security set-key-partition-list -S apple-tool:,apple: -s -l "$name" "$keychain" >/dev/null
    echo "Done: builds now sign without asking."
}

if security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
    echo "\"$name\" already exists in your login keychain."
    allow_codesign
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$tmp/cert.cnf" -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
# A throwaway password: security import needs one, and the file is deleted right after.
pass=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -name "$name" -passout "pass:$pass" -out "$tmp/cert.p12"

security import "$tmp/cert.p12" -k "$keychain" -P "$pass" -T /usr/bin/codesign
echo "Created \"$name\" in your login keychain."
allow_codesign
echo "Next: run ./build.sh install, then turn on axclick in Accessibility settings one last time."
