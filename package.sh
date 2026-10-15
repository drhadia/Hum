#!/bin/bash
# Builds the release app, wraps it in a disk image with an Applications shortcut,
# then notarizes and staples the image so Gatekeeper opens it on any Mac.
#   ./package.sh        creates build/Hum-<version>.dmg (and build/Hum.app)
#
# Notarization reads Apple ID credentials from a notarytool keychain profile, stored once with:
#   xcrun notarytool store-credentials hum-notary --apple-id <apple-id> --team-id <team-id>
# HUM_NOTARY_PROFILE picks a different profile; HUM_SKIP_NOTARIZE=1 stops before uploading to Apple.
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="${HUM_NOTARY_PROFILE:-hum-notary}"

./build.sh release

codesign --verify --strict build/Hum.app
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
DMG="build/Hum-$VERSION.dmg"

STAGE="$(mktemp -d)"
CERTS="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$CERTS"' EXIT
cp -R build/Hum.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Hum" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

# Sign the image with the app's own certificate, by hash: two certificates can share a name.
codesign -d --extract-certificates="$CERTS/cert" build/Hum.app 2>/dev/null
codesign --sign "$(shasum -a 1 "$CERTS/cert0" | cut -d' ' -f1)" --timestamp "$DMG"
echo "Created $DMG ($(du -h "$DMG" | cut -f1)), signed with: $(codesign -dvv "$DMG" 2>&1 | sed -n 's/^Authority=//p' | head -1)"

if [[ "${HUM_SKIP_NOTARIZE:-}" == "1" ]]; then
    echo "Skipped notarization: Gatekeeper will block this DMG on other Macs."
    exit 0
fi

echo "Notarizing (usually a few minutes)..."
RESULT="$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --output-format json)"
if [[ "$(plutil -extract status raw - <<<"$RESULT")" != "Accepted" ]]; then
    echo "Notarization failed:" >&2
    xcrun notarytool log "$(plutil -extract id raw - <<<"$RESULT")" --keychain-profile "$PROFILE" >&2
    exit 1
fi

xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "Ready to ship: $DMG"
