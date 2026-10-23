#!/usr/bin/env bash
# Ships a release: notarized DMG → signed Sparkle appcast → GitHub Release (vX.Y.Z).
#
# Prereqs: gh auth login · Developer ID cert · NOTARY_PROFILE (see release.sh) ·
#          Sparkle private key in the keychain (generate_keys --account blinko).
# Usage:   NOTARY_PROFILE=blinko-notary scripts/publish.sh [release-notes.md]
#          BLINKO_ALLOW_UNNOTARIZED=1 scripts/publish.sh [notes.md]   (until a Developer ID exists)
# Bump CFBundleShortVersionString / CFBundleVersion in Resources/Info.plist first.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/release.env

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"
BIN=.build/artifacts/sparkle/Sparkle/bin

gh auth status >/dev/null 2>&1 || { echo "error: run 'gh auth login' first" >&2; exit 1; }
if gh release view "$TAG" -R "$GITHUB_REPO" >/dev/null 2>&1; then
  echo "error: release $TAG already exists — bump the version in Resources/Info.plist" >&2; exit 1
fi
[[ -n "$(git status --porcelain)" ]] && { echo "error: commit your changes first" >&2; exit 1; }

DMG="dist/Blinko-$VERSION.dmg"
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  scripts/release.sh                      # signed + notarized + stapled
elif [[ -n "${BLINKO_ALLOW_UNNOTARIZED:-}" ]]; then
  # No Developer ID yet: ship the Apple Development-signed build. Sparkle still verifies the
  # EdDSA signature; first-time installs need "Open Anyway" once (see the DMG's note).
  echo "warning: publishing WITHOUT notarization (no Developer ID certificate)" >&2
  scripts/share-dmg.sh
  mv -f "dist/Blinko-$VERSION-share.dmg" "$DMG"
else
  echo "error: no Developer ID certificate. Set BLINKO_ALLOW_UNNOTARIZED=1 to publish an un-notarized build." >&2
  exit 1
fi

# Keep appcast history: start from the appcast of the current latest release.
UPDATES="dist/updates"
rm -rf "$UPDATES" && mkdir -p "$UPDATES"
gh release download -R "$GITHUB_REPO" --pattern appcast.xml --dir "$UPDATES" 2>/dev/null || true
cp "$DMG" "$UPDATES/"

# Release notes: argument file, or commit subjects since the previous tag.
NOTES="$UPDATES/Blinko-$VERSION.md"
if [[ -n "${1:-}" ]]; then
  cp "$1" "$NOTES"
else
  PREV=$(git describe --tags --abbrev=0 2>/dev/null || true)
  { echo "## Blinko $VERSION"; echo; git log --pretty='- %s' ${PREV:+$PREV..}HEAD; } > "$NOTES"
fi

"$BIN/generate_appcast" --account "$SPARKLE_KEY_ACCOUNT" \
  --download-url-prefix "https://github.com/$GITHUB_REPO/releases/download/$TAG/" \
  --embed-release-notes --maximum-deltas 0 \
  -o "$UPDATES/appcast.xml" "$UPDATES"

git tag -a "$TAG" -m "Blinko $VERSION"
git push origin HEAD "$TAG"
gh release create "$TAG" -R "$GITHUB_REPO" --title "Blinko $VERSION" --notes-file "$NOTES" \
  "$DMG" "$UPDATES/appcast.xml"
echo "Published $TAG — feed: https://github.com/$GITHUB_REPO/releases/latest/download/appcast.xml"
