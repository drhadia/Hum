#!/bin/bash
# The copy of Hum for other people: universal (Apple silicon + Intel), Developer ID signed, notarized,
# in a disk image with an Applications shortcut.
#   ./package.sh        creates build/release/Hum.app and build/Hum-<version>.dmg
#
# Needs, in this Mac's keychain:
#   - a "Developer ID Application" certificate (or set DEVELOPER_ID to the identity's full name)
#   - notarytool credentials, saved once with:
#       xcrun notarytool store-credentials hum-notary --apple-id <apple id> --team-id <team id>
#     (or set NOTARY_PROFILE to another profile name; NOTARY_PROFILE= skips notarization, for a local test)
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${DEVELOPER_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)}"
if [[ -z "$IDENTITY" ]]; then
    echo "No Developer ID Application certificate in the keychain; other Macs block apps signed any other way." >&2
    exit 1
fi
PROFILE="${NOTARY_PROFILE-hum-notary}"

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Hum"

APP="build/release/Hum.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Hum"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Notarization requires the hardened runtime and a secure timestamp. The entitlement lets the hardened app
# send Apple Events to Music and Spotify.
codesign --force --options runtime --timestamp --entitlements Hum.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
DMG="build/Hum-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Hum" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [[ -n "$PROFILE" ]]; then
    # Notarizing the disk image covers the app inside it; the stapled ticket lets it open offline.
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
else
    echo "Skipped notarization (NOTARY_PROFILE is empty): other Macs will refuse to open this disk image." >&2
fi
echo "Created $DMG ($(du -h "$DMG" | cut -f1)), signed with: $IDENTITY"
