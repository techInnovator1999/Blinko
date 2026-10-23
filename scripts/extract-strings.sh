#!/usr/bin/env bash
# Refreshes Resources/Localizable.xcstrings from the code, the way Xcode does it: the Swift
# compiler emits every localizable literal (Text, Button, LocalizedStringKey parameters,
# String(localized:)…) as .stringsdata, then xcstringstool merges them into the catalog.
# Strings no longer in the code are marked stale. Usage: scripts/extract-strings.sh
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=".build/strings/stringsdata"
# Clean build: an incremental one only emits .stringsdata for recompiled files, and sync
# would then drop every string from the others.
rm -rf .build/strings && mkdir -p "$OUT"
swift build --scratch-path .build/strings \
  -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$PWD/$OUT" >/dev/null
xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata "$OUT"/*.stringsdata
echo "Updated Resources/Localizable.xcstrings ($(xcrun xcstringstool print Resources/Localizable.xcstrings | wc -l | tr -d ' ') keys)"
