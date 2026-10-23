#!/usr/bin/env bash
# Builds a shareable (not notarized) DMG for friends/testers: dist/Blinko-<version>-share.dmg
# Use scripts/release.sh for a notarized public release once a Developer ID cert exists.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
BLINKO_UNIVERSAL=1 scripts/build.sh release
STAGE="$(mktemp -d)"
cp -R build/Blinko.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/How to open Blinko.txt" <<'TXT'
Blinko: a Dynamic Island for your Mac

1. Drag Blinko into the Applications folder.
2. Open Blinko from Applications.
   macOS will say it can't verify the developer (this build isn't notarized yet).
3. Open System Settings → Privacy & Security, scroll down, click "Open Anyway"
   next to the Blinko message, then confirm with your password.
4. Blinko lives in your notch. Hover it, click it, or press Control-Option-Space.

Optional permissions (asked when needed):
• Accessibility: replaces the volume/brightness pop-ups
• Calendar & Reminders: shows your next events

If music from browsers doesn't appear, run this once in Terminal:
  xattr -dr com.apple.quarantine /Applications/Blinko.app

Designed by OptimaGeeks · optimageeks.com
TXT
mkdir -p dist
DMG="dist/Blinko-$VERSION-share.dmg"
rm -f "$DMG"
hdiutil create -volname "Blinko $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null 2>&1
rm -rf "$STAGE"
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application|Apple Development/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$DMG"
echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
