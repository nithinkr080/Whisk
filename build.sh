#!/bin/bash
# Builds Whisk and packages it as build/Whisk.app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Whisk.app"
# UNIVERSAL=1 ./build.sh builds a binary for both Apple Silicon and Intel Macs (used for releases).
ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/Whisk"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Whisk"

# Icon
ICONSET="build/Whisk.iconset"
rm -rf "$ICONSET"
swift Scripts/make_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Whisk.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Whisk</string>
    <key>CFBundleIdentifier</key><string>io.github.nithinkr080.whisk</string>
    <key>CFBundleName</key><string>Whisk</string>
    <key>CFBundleDisplayName</key><string>Whisk</string>
    <key>CFBundleIconFile</key><string>Whisk</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSScreenCaptureUsageDescription</key><string>Whisk shows live previews of your windows in the switcher.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign with a fixed designated requirement (identifier only). Without it the requirement is the
# binary's hash, which changes on every rebuild, and macOS drops the Accessibility / Screen Recording grants.
codesign --force --deep --sign - -r='designated => identifier "io.github.nithinkr080.whisk"' "$APP"
echo "Built $APP"
