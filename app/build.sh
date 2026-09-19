#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

APP_NAME="PC Tunes"
BUNDLE="$APP_NAME.app"

swift build -c release --product PCTunes

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$(swift build -c release --product PCTunes --show-bin-path)/PCTunes" \
   "$BUNDLE/Contents/MacOS/PCTunes"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>PC Tunes</string>
    <key>CFBundleDisplayName</key>
    <string>PC Tunes</string>
    <key>CFBundleIdentifier</key>
    <string>com.pcinfinity.pc-tunes</string>
    <key>CFBundleExecutable</key>
    <string>PCTunes</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <!-- Required: a menu bar accessory. On macOS 26.6 a bundled app WITHOUT this
         fails to get its status item adopted into the menu bar (the item lands
         off-screen). It also keeps the app out of the Dock and the app switcher. -->
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature. SMAppService refuses to register an unsigned bundle.
codesign --force --sign - "$BUNDLE"

# Re-register with Launch Services. It caches Info.plist per bundle id, so a machine
# that once ran a build WITHOUT `LSUIElement` would keep the stale entry and the status
# item would never be adopted into the menu bar (see App.swift). Unregister first so the
# stale entry is actually replaced.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -u "$BUNDLE" >/dev/null 2>&1 || true
    "$LSREGISTER" -f "$BUNDLE" >/dev/null 2>&1 || true
fi

# The extension is not built, but it ships with the app and breaks just as visibly.
# `node --check` alone is not enough — it parses happily past a call to a function
# that was deleted — so the reference check runs here too, where it cannot be
# forgotten. Skipped rather than failed when node is absent: it is not a build
# dependency, and the app builds fine without it.
EXTENSION="$HERE/../extension"
if command -v node >/dev/null 2>&1; then
    for file in "$EXTENSION"/*.js; do
        node --check "$file"
    done
    node "$EXTENSION/check.mjs" "$EXTENSION/inject.js" "$EXTENSION/content.js" "$EXTENSION/sw.js"
else
    echo "node not found — skipping the extension checks"
fi

echo "Built $PWD/$BUNDLE"
