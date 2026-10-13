#!/bin/bash
# Builds Hum.app into ./build and (optionally) launches it.
#   ./build.sh          build only
#   ./build.sh run      build, then (re)launch
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Hum"

APP="build/Hum.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Hum"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Icon: `./build/Hum.app/Contents/MacOS/Hum --icon Resources/AppIcon.iconset && iconutil -c icns Resources/AppIcon.iconset`
# regenerates Resources/AppIcon.icns from Sources/Hum/AppIconArt.swift.

# A stable signing identity keeps the Local Network / Automation permissions across rebuilds.
IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)"
codesign --force --deep --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "run" ]]; then
    pkill -x Hum 2>/dev/null || true
    open "$APP"
fi
