#!/bin/bash
# Builds a universal Whisk.app and packages it for a GitHub release:
#   dist/Whisk-<version>-macOS.zip   (the .app, zipped with ditto so the signature survives)
#   dist/Whisk-<version>.dmg         (drag-to-Applications disk image)
# Usage: Scripts/package_release.sh [version]     (defaults to the version in build.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(grep -A1 CFBundleShortVersionString build.sh | grep -o '<string>[^<]*' | head -1 | sed 's/<string>//')}"
UNIVERSAL=1 ./build.sh

mkdir -p dist
ZIP="dist/Whisk-${VERSION}-macOS.zip"
DMG="dist/Whisk-${VERSION}.dmg"

ditto -c -k --sequesterRsrc --keepParent build/Whisk.app "$ZIP"

STAGE="$(mktemp -d)"
cp -R build/Whisk.app "$STAGE/Whisk.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Whisk" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo
echo "Packaged Whisk ${VERSION}:"
shasum -a 256 "$ZIP" "$DMG"
