#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "Building…"
xcodegen generate >/dev/null
xcodebuild -scheme JSONClipboardFormatter -configuration Debug -destination 'platform=macOS' build -quiet

SRC=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/JSONClipboardFormatter-*/Build/Products/Debug/JSON\ Clipboard\ Formatter.app | head -1)
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/JSON Clipboard Formatter.app"

mkdir -p "$DEST_DIR"
# Kill every running copy (Applications + DerivedData + any stray).
pkill -f "JSON Clipboard Formatter.app/Contents/MacOS/JSON Clipboard Formatter" 2>/dev/null || true
pkill -f "JSON Clipboard Formatter" 2>/dev/null || true
sleep 0.4
# Make sure nothing is left
if pgrep -f "JSON Clipboard Formatter.app/Contents/MacOS" >/dev/null; then
  pkill -9 -f "JSON Clipboard Formatter.app/Contents/MacOS" 2>/dev/null || true
  sleep 0.2
fi

# Update in place with ditto (avoids deleting the bundle, keeps Accessibility happier).
if [ -d "$DEST" ]; then
  ditto "$SRC" "$DEST"
else
  cp -R "$SRC" "$DEST"
fi

open "$DEST"

echo ""
echo "Launched from: $DEST"
echo "Click { } and check: Accessibility + Last gesture status."
