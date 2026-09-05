#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

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
    <string>com.pcinfinity.pctunes</string>
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
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature. SMAppService refuses to register an unsigned bundle.
codesign --force --sign - "$BUNDLE"

# The extension is not built, but it ships with the app and breaks just as visibly.
# `node --check` alone is not enough — it parses happily past a call to a function
# that was deleted — so the reference check runs here too, where it cannot be
# forgotten. Skipped rather than failed when node is absent: it is not a build
# dependency, and the app builds fine without it.
EXTENSION="$(cd "$(dirname "$0")/../extension" && pwd)"
if command -v node >/dev/null 2>&1; then
    for file in "$EXTENSION"/*.js; do
        node --check "$file"
    done
    node "$EXTENSION/check.mjs" "$EXTENSION/inject.js" "$EXTENSION/content.js" "$EXTENSION/sw.js"
else
    echo "node not found — skipping the extension checks"
fi

echo "Built $PWD/$BUNDLE"
