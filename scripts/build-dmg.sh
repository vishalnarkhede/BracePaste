#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :MARKETING_VERSION' JSONClipboardFormatter/Resources/Info.plist 2>/dev/null || true)}"
if [[ -z "${VERSION}" || "${VERSION}" == *"Does Not Exist"* ]]; then
  VERSION=$(grep -E 'MARKETING_VERSION:' project.yml | head -1 | awk '{print $2}' | tr -d '"' || echo "1.0.0")
fi
VERSION="${VERSION:-1.0.0}"

APP_NAME="JSON Clipboard Formatter"
SCHEME="JSONClipboardFormatter"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-stage"
DMG_PATH="$DIST/JSONClipboardFormatter-${VERSION}.dmg"
VOLUME_NAME="JSON Clipboard Formatter"

echo "==> Generating Xcode project"
command -v xcodegen >/dev/null || { echo "Install xcodegen: brew install xcodegen"; exit 1; }
xcodegen generate >/dev/null

echo "==> Building Release ($VERSION)"
xcodebuild \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DIST/DerivedData" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  build \
  -quiet

APP_SRC=$(find "$DIST/DerivedData/Build/Products/Release" -maxdepth 1 -name "*.app" | head -1)
if [[ -z "$APP_SRC" ]]; then
  echo "Release .app not found"
  exit 1
fi

echo "==> App: $APP_SRC"
rm -rf "$STAGE" "$DMG_PATH"
mkdir -p "$STAGE" "$DIST"

ditto "$APP_SRC" "$STAGE/$APP_NAME.app"
ln -sf /Applications "$STAGE/Applications"

# Ad-hoc sign the shipped app bundle for local Gatekeeper friendliness.
codesign --force --deep --sign - "$STAGE/$APP_NAME.app" 2>/dev/null || true

echo "==> Creating DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGE"

echo ""
echo "Created: $DMG_PATH"
ls -lh "$DMG_PATH"
