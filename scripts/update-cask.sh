#!/bin/bash
# Usage: ./scripts/update-cask.sh <version>
# Points the Homebrew cask at the GitHub release for <version> (must already be published).
set -euo pipefail

VERSION="${1:?usage: update-cask.sh <version>}"
TAP_DIR="${TAP_DIR:-$HOME/projects/homebrew-tap}"
CASK="$TAP_DIR/Casks/bracepaste.rb"
URL="https://github.com/vishalnarkhede/BracePaste/releases/download/v${VERSION}/BracePaste-${VERSION}.dmg"

echo "==> Fetching $URL"
TMP=$(mktemp)
curl -fsSL "$URL" -o "$TMP"
SHA=$(shasum -a 256 "$TMP" | awk '{print $1}')
rm -f "$TMP"
echo "==> sha256: $SHA"

sed -i '' \
  -e "s/^  version \".*\"/  version \"${VERSION}\"/" \
  -e "s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" \
  "$CASK"

cd "$TAP_DIR"
git add Casks/bracepaste.rb
git commit -m "bracepaste ${VERSION}"
git push origin main
echo "==> Cask updated to ${VERSION}"
