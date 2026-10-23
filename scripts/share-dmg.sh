#!/usr/bin/env bash
# Builds a shareable (not notarized) DMG for friends/testers: dist/Blinko-<version>-share.dmg
# Use scripts/release.sh for a notarized public release once a Developer ID cert exists.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
BLINKO_UNIVERSAL=1 scripts/build.sh release
mkdir -p dist
DMG="dist/Blinko-$VERSION-share.dmg"
scripts/make-dmg.sh build/Blinko.app "$DMG" "$VERSION" >/dev/null
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application|Apple Development/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$DMG"
echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
