#!/usr/bin/env bash
# Renders the Blinko logo (design/logo.swift, "lid" variant) into Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"
for base in 16 32 128 256 512; do
  swift design/logo.swift lid "$SET/icon_${base}x${base}.png" "$base"
  swift design/logo.swift lid "$SET/icon_${base}x${base}@2x.png" "$((base * 2))"
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
swift design/logo.swift lid design/logo-1024.png 1024
echo "Wrote Resources/AppIcon.icns and design/logo-1024.png"
