# JSON Clipboard Formatter

Native macOS menu bar app that formats JSON from your clipboard with a double **⌘C** gesture.

All processing is local. No network. No clipboard history.

## Install (DMG)

1. Download the latest **`.dmg`** from [Releases](https://github.com/vishalnarkhede/JSONClipboardFormatter/releases).
2. Open the DMG and drag **JSON Clipboard Formatter** into **Applications**.
3. Launch it from Applications (or Spotlight).
4. Grant **Accessibility** when prompted (required for double-⌘C detection).

> **Gatekeeper note:** The release build is ad-hoc signed (no Apple Developer ID). On first open, right-click the app → **Open**, or allow it under **System Settings → Privacy & Security**.

## Usage

1. Select JSON (or JSON-like text) in any app.
2. Press **⌘C** twice within ~2 seconds (configurable).
3. If valid JSON is found, the clipboard is replaced with formatted JSON and a popup appears.
4. If not JSON, nothing happens — ordinary double-copy stays quiet.

You can also use **Format Clipboard** from the `{ }` menu bar icon.

## Features

- Double-⌘C system-wide trigger (non-consuming)
- Extracts JSON from code fences, escaped strings, and surrounding log text
- Strict JSON only (no Python dicts / JS literals / trailing commas)
- Syntax-highlighted floating editor
- Copy / Copy Minified / Format Again / safe clipboard undo
- Optional global shortcut, indentation settings, open at login

## Requirements

- macOS 13.0 (Ventura) or later

## Build from source

```bash
brew install xcodegen   # if needed
cd JSONClipboardFormatter
xcodegen generate
xcodebuild -scheme JSONClipboardFormatter -configuration Release -destination 'platform=macOS' build
```

Or open `JSONClipboardFormatter.xcodeproj` in Xcode.

### Create a DMG locally

```bash
./scripts/build-dmg.sh
```

Output: `dist/JSONClipboardFormatter-<version>.dmg`

## Privacy

- Clipboard content never leaves your Mac
- No analytics / telemetry by default
- Only the latest result + undo snapshot are kept in memory (cleared on quit)

## Permissions

**Accessibility** is required for double-⌘C detection. Without it, menu-bar **Format Clipboard** still works.

## License

[MIT](LICENSE)
