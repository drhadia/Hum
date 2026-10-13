#!/bin/bash
# Builds the release app and wraps it in a disk image with an Applications shortcut.
#   ./package.sh        creates build/Hum-<version>.dmg (and build/Hum.app)
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

codesign --verify --deep --strict build/Hum.app
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
DMG="build/Hum-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R build/Hum.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Hum" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
