#!/bin/bash
# Renders packaging/homebrew/axclick.rb for a published release and writes it into a checkout
# of the 5uvarna/homebrew-tap repository. It does not commit or push the tap.
#
#   scripts/release-formula.sh 0.1.0 ../homebrew-tap
#
# The tag v<version> and its GitHub release must already exist. The formula downloads the source
# from a file attached to the release (axclick-<version>.tar.gz) instead of GitHub's tag archive,
# because GitHub counts release downloads: that count is the number of Homebrew installs.
# This script attaches that file if the release doesn't have it yet. It never replaces one.
set -euo pipefail

version=${1:?usage: release-formula.sh <version> <tap checkout>}
tap=$(cd "${2:?usage: release-formula.sh <version> <tap checkout>}" && pwd) # before the cd below
cd "$(dirname "$0")/.."
repo=5uvarna/axclick
name="axclick-$version.tar.gz"
url="https://github.com/$repo/releases/download/v$version/$name"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if gh release view "v$version" --repo "$repo" --json assets --jq '.assets[].name' | grep -qx "$name"; then
    echo "the release already has $name"
else
    curl -fsSL "https://github.com/$repo/archive/refs/tags/v$version.tar.gz" -o "$tmp/$name"
    gh release upload "v$version" "$tmp/$name" --repo "$repo"
    echo "attached $name to v$version"
fi

sha=$(curl -fsSL "$url" | shasum -a 256 | cut -d' ' -f1)
mkdir -p "$tap/Formula"
sed -e "s|@VERSION@|$version|g" -e "s|@SHA256@|$sha|" packaging/homebrew/axclick.rb > "$tap/Formula/axclick.rb"

echo "wrote $tap/Formula/axclick.rb (v$version, sha256 $sha)"
echo "next: commit and push it in $tap"
echo "Homebrew installs so far: gh api repos/$repo/releases --jq '.[].assets[] | select(.name|endswith(\".tar.gz\")) | \"\\(.name) \\(.download_count)\"'"
