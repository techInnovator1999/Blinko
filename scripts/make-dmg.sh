#!/usr/bin/env bash
# Builds the designed install DMG: background art, icon layout, window size, volume icon.
# Usage: scripts/make-dmg.sh <Blinko.app> <out.dmg> [version]
#
# dmgbuild lays out the image; Finder then re-applies the window bounds and view options
# itself (macOS 26+ Finder ignores window sizes in third-party .DS_Store files), and the
# image is compressed afterwards. Finder may ask once for Automation permission.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$1"; OUT="$2"; VERSION="${3:-}"
NAME="Blinko${VERSION:+ $VERSION}"
W=920; H=400
WORK="$(mktemp -d)"
cleanup() { [[ -d "/Volumes/$NAME" ]] && hdiutil detach "/Volumes/$NAME" -quiet -force 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

[[ -x .venv-tools/bin/python ]] || { uv venv -q --python 3.12 .venv-tools && uv pip install -q --python .venv-tools/bin/python dmgbuild; }
if [[ -d "/Volumes/$NAME" ]]; then echo "error: eject the mounted \"$NAME\" volume first" >&2; exit 1; fi

swift design/dmg/background.swift "$WORK" "$VERSION" >/dev/null
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$WORK/bg.tiff" >/dev/null 2>&1

.venv-tools/bin/python -m dmgbuild -s design/dmg/settings.py \
  -D app="$APP" -D background="$WORK/bg.tiff" -D icon="Resources/AppIcon.icns" -D format=UDRW \
  -D w=$W -D h=$H "$NAME" "$WORK/rw.dmg" >/dev/null

hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen -quiet
osascript >/dev/null <<OSA
tell application "Finder"
  tell disk "$NAME"
    open
    set w to container window
    set current view of w to icon view
    set toolbar visible of w to false
    set statusbar visible of w to false
    set sidebar width of w to 0
    set bounds of w to {200, 140, 200 + $W, 140 + $H + 28}
    set opts to icon view options of w
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background.tiff"
    set position of item "$(basename "$APP")" of w to {300, 190}
    set position of item "Applications" of w to {620, 190}
    -- Park dot-files far outside the window, for people who show hidden files.
    set n to 0
    repeat with f in (every item of w whose name begins with ".")
      set position of f to {2400 + n * 140, 2400}
      set n to n + 1
    end repeat
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
rm -rf "/Volumes/$NAME/.fseventsd" "/Volumes/$NAME/.Trashes"
sync
hdiutil detach "/Volumes/$NAME" -quiet
rm -f "$OUT"
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT" -quiet
echo "Created $OUT ($(du -h "$OUT" | cut -f1))"
