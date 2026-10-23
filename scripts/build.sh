#!/usr/bin/env bash
# Builds Blinko.app into ./build. Usage: scripts/build.sh [debug|release] [--run]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Blinko.app"

swift build -c "$CONFIG" --arch arm64
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/Blinko"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Blinko"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# MediaRemote bridge: a dylib loaded by Apple's platform perl (see Helper/BlinkoMedia.m).
clang -dynamiclib -fobjc-arc -O2 -arch arm64 -arch arm64e -mmacosx-version-min=14.0 \
  -framework Foundation -o "$APP/Contents/Resources/BlinkoMedia.dylib" Helper/BlinkoMedia.m 2>/dev/null
cp Helper/blinko-media.pl "$APP/Contents/Resources/"
codesign --force --sign - "$APP/Contents/Resources/BlinkoMedia.dylib" >/dev/null

# Prefer a real signing identity so TCC grants (Accessibility, Calendar) survive rebuilds.
IDENTITY="${BLINKO_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" --options runtime \
  --entitlements Resources/Blinko.entitlements "$APP" >/dev/null
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

if [[ "${2:-}" == "--run" ]]; then
  pkill -x Blinko 2>/dev/null || true
  open "$APP"
fi
