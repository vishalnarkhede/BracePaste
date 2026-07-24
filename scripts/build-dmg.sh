#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-1.1.0}"
APP_NAME="BracePaste"
SCHEME="JSONClipboardFormatter"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-stage"
DMG_PATH="$DIST/BracePaste-${VERSION}.dmg"
VOLUME_NAME="BracePaste"

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
  MARKETING_VERSION="$VERSION" \
  build \
  -quiet

APP_SRC=$(find "$DIST/DerivedData/Build/Products/Release" -maxdepth 1 -name "BracePaste.app" | head -1)
if [[ -z "$APP_SRC" ]]; then
  APP_SRC=$(find "$DIST/DerivedData/Build/Products/Release" -maxdepth 1 -name "*.app" | head -1)
fi
if [[ -z "$APP_SRC" ]]; then
  echo "Release .app not found"
  exit 1
fi

echo "==> App: $APP_SRC"
rm -rf "$STAGE" "$DMG_PATH"
mkdir -p "$STAGE" "$DIST"

ditto "$APP_SRC" "$STAGE/$APP_NAME.app"
ln -sf /Applications "$STAGE/Applications"

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
