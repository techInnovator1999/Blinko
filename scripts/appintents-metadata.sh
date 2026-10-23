#!/usr/bin/env bash
# Generates Metadata.appintents (what Shortcuts reads to list Blinko's actions) for a SwiftPM
# build, the way Xcode does: the compiler already emits .swiftconstvalues for App Intents
# types; appintentsmetadataprocessor turns them into the metadata bundle.
# Usage: scripts/appintents-metadata.sh <debug|release> <output Resources dir>
# Best-effort: without Xcode or const values it warns and exits 0 (URL scheme + CLI still work).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="$1"
OUT="$2"
CAP="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}"

warn() { echo "warning: App Intents metadata skipped ($1); Shortcuts actions won't be listed" >&2; exit 0; }

xcrun --find appintentsmetadataprocessor >/dev/null 2>&1 || warn "appintentsmetadataprocessor needs Xcode"
OBJ=".build/out/Intermediates.noindex/Blinko.build/$CAP/Blinko-p.build/Objects-normal/arm64"
[[ -d "$OBJ" ]] || OBJ="$(find .build -type d -path "*$CAP*Blinko*Objects-normal/arm64" 2>/dev/null | head -1)"
[[ -n "$OBJ" && -d "$OBJ" ]] || warn "no compiler intermediates found"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
find "$OBJ" -name '*.swiftconstvalues' > "$WORK/constvals.txt"
[[ -s "$WORK/constvals.txt" ]] || warn "the compiler emitted no .swiftconstvalues"
find "$PWD/Sources/Blinko" -name '*.swift' > "$WORK/sources.txt"

xcrun appintentsmetadataprocessor \
  --output "$WORK/out" \
  --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
  --module-name Blinko \
  --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
  --xcode-version "$(xcodebuild -version 2>/dev/null | awk '/Build version/ {print $3}')" \
  --platform-family macOS \
  --deployment-target 14.0 \
  --target-triple arm64-apple-macos14.0 \
  --source-file-list "$WORK/sources.txt" \
  --swift-const-vals-list "$WORK/constvals.txt" \
  --quiet-warnings >/dev/null 2>"$WORK/log" || warn "processor failed: $(tail -1 "$WORK/log")"
[[ -d "$WORK/out/Metadata.appintents" ]] || warn "processor produced no output"
rm -rf "$OUT/Metadata.appintents"
cp -R "$WORK/out/Metadata.appintents" "$OUT/"
