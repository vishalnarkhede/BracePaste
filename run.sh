#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "Building…"
xcodegen generate >/dev/null
xcodebuild -scheme JSONClipboardFormatter -configuration Debug -destination 'platform=macOS' build -quiet

SRC=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/JSONClipboardFormatter-*/Build/Products/Debug/BracePaste.app 2>/dev/null | head -1)
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/BracePaste.app"

mkdir -p "$DEST_DIR"
pkill -f "BracePaste.app/Contents/MacOS/BracePaste" 2>/dev/null || true
pkill -f "JSON Clipboard Formatter" 2>/dev/null || true
sleep 0.4
if pgrep -f "BracePaste.app/Contents/MacOS" >/dev/null; then
  pkill -9 -f "BracePaste.app/Contents/MacOS" 2>/dev/null || true
  sleep 0.2
fi

if [ -d "$DEST" ]; then
  ditto "$SRC" "$DEST"
else
  cp -R "$SRC" "$DEST"
fi

open "$DEST"
echo ""
echo "Launched from: $DEST"
echo "Look for the BracePaste { } icon in the menu bar."
