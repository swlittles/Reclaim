#!/bin/bash
# Publish a signed Sparkle feed alongside the notarized release assets.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SPARKLE_ED_PRIVATE_KEY:?Configure the Sparkle signing secret}"
VERSION=$(cat VERSION)
WORK=$(mktemp -d "$PWD/.build/appcast.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
NAME="Reclaim-$VERSION-macos-universal"
cp "release-assets/$NAME.dmg" "$WORK/"
bash scripts/release-notes.sh > "$WORK/$NAME.md"
TOOLS="$PWD/.build/distribution-arm64/artifacts/sparkle/Sparkle/bin"
# Signatures cover the stapled DMG. Keep the private key on stdin, out of arguments, files, and logs.
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$TOOLS/generate_appcast" \
    --ed-key-file - --maximum-deltas 0 --embed-release-notes \
    --download-url-prefix "https://github.com/swlittles/Reclaim/releases/download/v$VERSION/" "$WORK"
python3 scripts/validate-appcast.py "$WORK/appcast.xml" "$VERSION" "$(cat BUILD_NUMBER)" "release-assets/$NAME.dmg"
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$TOOLS/sign_update" --ed-key-file - --verify "$WORK/appcast.xml"
cp "$WORK/appcast.xml" release-assets/appcast.xml

# Independently enforce that the release signing secret matches the public key shipped in the app.
swift scripts/verify-update.swift "${RECLAIM_SPARKLE_PUBLIC_KEY_FILE:-Config/SparklePublicKey.txt}" release-assets/appcast.xml "release-assets/$NAME.dmg"
