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

echo "Built $PWD/$BUNDLE"
