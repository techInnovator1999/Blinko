#!/usr/bin/env bash
# Builds a signed, notarized, stapled DMG in ./dist.
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your keychain (Xcode → Settings → Accounts).
#   2. A notary profile:  xcrun notarytool store-credentials blinko-notary \
#        --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
# Then:  NOTARY_PROFILE=blinko-notary scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${BLINKO_RELEASE_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
if [[ -z "$IDENTITY" ]]; then
  echo "error: no 'Developer ID Application' identity found (needed for notarization)." >&2
  echo "       Create one in Xcode → Settings → Accounts → Manage Certificates." >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
# build.sh signs everything inside-out; BLINKO_TIMESTAMP adds the secure timestamp notarization requires.
BLINKO_UNIVERSAL=1 BLINKO_SIGN_IDENTITY="$IDENTITY" BLINKO_TIMESTAMP=1 scripts/build.sh release
APP="build/Blinko.app"
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP/Contents/Resources/BlinkoMedia.dylib"
codesign --force --timestamp --options runtime --entitlements Resources/Blinko.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p dist
DMG="dist/Blinko-$VERSION.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Blinko $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
else
  echo "note: NOTARY_PROFILE not set — DMG is signed but not notarized."
fi
echo "Created $DMG"
