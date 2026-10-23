#!/usr/bin/env bash
# Builds Blinko.app into ./build. Usage: scripts/build.sh [debug|release] [--run]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Blinko.app"

# BLINKO_UNIVERSAL=1 builds Apple Silicon + Intel (for distribution).
ARCHS=(--arch arm64)
[[ -n "${BLINKO_UNIVERSAL:-}" ]] && ARCHS=(--arch arm64 --arch x86_64)
swift build -c "$CONFIG" "${ARCHS[@]}"
BIN="$(swift build -c "$CONFIG" "${ARCHS[@]}" --show-bin-path)/Blinko"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Blinko"
# `blinko` CLI (automation + Claude Code hook client). Helpers/, not MacOS/: the volume is
# case-insensitive, so "blinko" would collide with "Blinko".
mkdir -p "$APP/Contents/Helpers"
cp "$(dirname "$BIN")/blinko-cli" "$APP/Contents/Helpers/blinko"
cp Resources/Info.plist "$APP/Contents/Info.plist"
source scripts/release.env
# Sparkle feed: the appcast is attached to the latest GitHub release.
/usr/libexec/PlistBuddy -c "Set :SUFeedURL https://github.com/$GITHUB_REPO/releases/latest/download/appcast.xml" "$APP/Contents/Info.plist"

# Embed Sparkle.framework (symlinks preserved) and sign its helpers inside-out.
SPARKLE_FW=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/optimageeks-mark.png "$APP/Contents/Resources/"
# Shortcuts actions (App Intents metadata, best-effort; see the script).
scripts/appintents-metadata.sh "$CONFIG" "$APP/Contents/Resources"

# Localisation: compile the String Catalog into <lang>.lproj/Localizable.strings in the main
# bundle, where SwiftUI's Text("…") and String(localized:) look by default. English is the
# source language (keys are the English text), so it needs no table of its own.
# Refresh the catalog from the code with scripts/extract-strings.sh.
mkdir -p "$APP/Contents/Resources/en.lproj"
if xcrun --find xcstringstool >/dev/null 2>&1; then
  xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources" >/dev/null
else
  echo "warning: xcstringstool not found (needs Xcode); shipping English only" >&2
fi

# MediaRemote bridge: a dylib loaded by Apple's platform perl (see Helper/BlinkoMedia.m).
clang -dynamiclib -fobjc-arc -O2 -arch arm64 -arch arm64e -arch x86_64 -mmacosx-version-min=14.0 \
  -framework Foundation -o "$APP/Contents/Resources/BlinkoMedia.dylib" Helper/BlinkoMedia.m 2>/dev/null
cp Helper/blinko-media.pl "$APP/Contents/Resources/"
codesign --force --sign - "$APP/Contents/Resources/BlinkoMedia.dylib" >/dev/null

# Prefer a real signing identity so TCC grants (Accessibility, Calendar) survive rebuilds.
IDENTITY="${BLINKO_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
SIGN=(codesign --force --sign "${IDENTITY:--}" --options runtime ${BLINKO_TIMESTAMP:+--timestamp})
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
"${SIGN[@]}" "$FW/XPCServices/Installer.xpc" "$FW/XPCServices/Downloader.xpc" >/dev/null 2>&1
"${SIGN[@]}" "$FW/Autoupdate" "$FW/Updater.app" >/dev/null 2>&1
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework" >/dev/null 2>&1
"${SIGN[@]}" "$APP/Contents/Helpers/blinko" >/dev/null
"${SIGN[@]}" --entitlements Resources/Blinko.entitlements "$APP" >/dev/null
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

if [[ "${2:-}" == "--run" ]]; then
  pkill -x Blinko 2>/dev/null || true
  # Wait for the old instance to exit, or LaunchServices refuses the open (error -600).
  for _ in {1..30}; do pgrep -x Blinko >/dev/null || break; sleep 0.1; done
  open "$APP"
fi
