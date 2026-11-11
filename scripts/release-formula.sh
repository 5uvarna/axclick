#!/bin/bash
# Renders packaging/homebrew/axclick.rb for a published release and writes it into a checkout
# of the 5uvarna/homebrew-tap repository. It does not commit or push.
#
#   scripts/release-formula.sh 0.1.0 ../homebrew-tap
#
# The tag v<version> must already be pushed to GitHub, since the checksum is of GitHub's tarball.
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:?usage: release-formula.sh <version> <tap checkout>}
tap=${2:?usage: release-formula.sh <version> <tap checkout>}
url="https://github.com/5uvarna/axclick/archive/refs/tags/v$version.tar.gz"

sha=$(curl -fsSL "$url" | shasum -a 256 | cut -d' ' -f1)
mkdir -p "$tap/Formula"
sed -e "s|@VERSION@|$version|" -e "s|@SHA256@|$sha|" packaging/homebrew/axclick.rb > "$tap/Formula/axclick.rb"

echo "wrote $tap/Formula/axclick.rb (v$version, sha256 $sha)"
echo "next: commit and push it in $tap"
