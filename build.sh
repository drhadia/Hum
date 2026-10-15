#!/bin/bash
# Builds Hum.app into ./build and (optionally) launches it.
#   ./build.sh            dev build only (Apple Development signature, for this Mac)
#   ./build.sh run        dev build, then (re)launch
#   ./build.sh release    universal build signed with Developer ID, ready for notarization (see package.sh)
# HUM_SIGN_IDENTITY overrides the certificate picked from the keychain.
#
# Dev builds are "Hum Dev" (com.hitesh.Hum.dev). macOS ties each permission to the app's signature, so a dev
# build sharing the release's bundle ID would take its Accessibility grant away every time the other one runs.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"

SWIFT_FLAGS=(-c release)
[[ "$MODE" == "release" ]] && SWIFT_FLAGS+=(--arch arm64 --arch x86_64)
swift build "${SWIFT_FLAGS[@]}"
BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)/Hum"

APP="build/Hum.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Hum"
cp Info.plist "$APP/Contents/Info.plist"
if [[ "$MODE" != "release" ]]; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.hitesh.Hum.dev' \
        -c 'Set :CFBundleName Hum Dev' -c 'Set :CFBundleDisplayName Hum Dev' "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Icon: `./build/Hum.app/Contents/MacOS/Hum --icon Resources/AppIcon.iconset && iconutil -c icns Resources/AppIcon.iconset`
# regenerates Resources/AppIcon.icns from Sources/Hum/AppIconArt.swift.

# A stable signing identity keeps the Local Network / Automation permissions across rebuilds.
# Prints "<sha1> <name>" of the first matching certificate. Signing goes by hash, because two
# certificates can share a name and codesign refuses an ambiguous one.
find_identity() {
    security find-identity -v -p codesigning | sed -n "s/^ *[0-9]*) \([0-9A-F]*\) \"\($1[^\"]*\)\".*/\1 \2/p" | head -1
}

if [[ "$MODE" == "release" ]]; then KIND="Developer ID Application"; else KIND="Apple Development"; fi
FOUND="$(find_identity "$KIND")"
SIGN="${HUM_SIGN_IDENTITY:-${FOUND%% *}}"
LABEL="${HUM_SIGN_IDENTITY:-${FOUND#* }}"

# Dev builds use the hardened runtime too, so they behave like the notarized release.
if [[ "$MODE" == "release" ]]; then
    if [[ -z "$SIGN" ]]; then
        echo "No Developer ID Application certificate in the keychain." >&2
        exit 1
    fi
    codesign --force --options runtime --timestamp --entitlements Hum.entitlements --sign "$SIGN" "$APP"
else
    codesign --force --options runtime --entitlements Hum.entitlements --sign "${SIGN:--}" "$APP"
fi
echo "Built $APP (signed with: ${LABEL:-ad-hoc})"

if [[ "$MODE" == "run" ]]; then
    # Only the dev build: an installed release can keep running beside it.
    pkill -f "$PWD/$APP/Contents/MacOS/Hum" 2>/dev/null || true
    open "$APP"
fi
