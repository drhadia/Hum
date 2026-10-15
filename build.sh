#!/bin/bash
# Dev build of Hum into ./build and (optionally) launches it. The copy for other people: ./package.sh.
#   ./build.sh          build only
#   ./build.sh run      build, then (re)launch
#
# This is "Hum Dev" (com.hitesh.Hum.dev). macOS ties each permission to the app's signature, so a dev build
# sharing the release's bundle ID would take its Accessibility grant away every time the other one runs.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Hum"

APP="build/Hum.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Hum"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.hitesh.Hum.dev' \
    -c 'Set :CFBundleName Hum Dev' -c 'Set :CFBundleDisplayName Hum Dev' "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Icon: `./build/Hum.app/Contents/MacOS/Hum --icon Resources/AppIcon.iconset && iconutil -c icns Resources/AppIcon.iconset`
# regenerates Resources/AppIcon.icns from Sources/Hum/AppIconArt.swift.

# A stable signing identity keeps the dev build's permissions across rebuilds. Hardened runtime and the
# entitlements match the release, so anything the release would block fails here first.
IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)"
codesign --force --options runtime --entitlements Hum.entitlements --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "run" ]]; then
    pkill -f "$PWD/$APP/Contents/MacOS/Hum" 2>/dev/null || true
    open "$APP"
fi
