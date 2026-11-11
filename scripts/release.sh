#!/bin/bash
# Build a universal DMG + ZIP. Stable distribution requires Developer ID + notarization.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-signed}"
[[ "$MODE" = signed || "$MODE" = preview ]] || { echo 'Usage: release.sh [signed|preview]' >&2; exit 1; }
VERSION=$(cat VERSION)
TEAM_ID="${APPLE_TEAM_ID:-KQFYGC7SWB}"
if [ "$MODE" = signed ]; then
    : "${RECLAIM_SIGNING_IDENTITY:?Set a Developer ID Application signing identity}"
    : "${NOTARY_PROFILE:?Set a notarytool Keychain profile}"
    [[ "$RECLAIM_SIGNING_IDENTITY" != - ]] || { echo 'Stable releases cannot use ad-hoc signing.' >&2; exit 1; }
else
    export RECLAIM_SIGNING_IDENTITY=-
fi
export RECLAIM_OUTPUT_DIR="$PWD/release-build"
export RECLAIM_UNIVERSAL=1
export RECLAIM_BUILD_VARIANT=production
bash scripts/test.sh
bash scripts/build.sh
APP="$RECLAIM_OUTPUT_DIR/Reclaim.app"
mkdir -p release-assets
WORK=$(mktemp -d "$PWD/release-build/.package.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
NAME="Reclaim-$VERSION-macos-universal"
if [ "$MODE" = preview ]; then NAME="Reclaim-$VERSION-preview-macos-universal"; fi

notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$WORK/notary.json"
    if ! python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1])).get("status") != "Accepted")' "$WORK/notary.json"; then
        cat "$WORK/notary.json" >&2; exit 1
    fi
}

if [ "$MODE" = signed ]; then
    signature=$(codesign -dvv "$APP" 2>&1)
    [[ "$signature" == *"Authority=Developer ID Application:"* && "$signature" == *"TeamIdentifier=$TEAM_ID"* ]] || { echo 'Wrong signing certificate or team.' >&2; exit 1; }
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/notarize.zip"
    notarize "$WORK/notarize.zip"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
fi

bash scripts/package-dmg.sh "$APP" "$WORK/$NAME.dmg" "$MODE"
if [ "$MODE" = signed ]; then
    codesign --timestamp --sign "$RECLAIM_SIGNING_IDENTITY" "$WORK/$NAME.dmg"
    notarize "$WORK/$NAME.dmg"
    xcrun stapler staple "$WORK/$NAME.dmg"
    xcrun stapler validate "$WORK/$NAME.dmg"
fi
hdiutil verify "$WORK/$NAME.dmg" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/$NAME.zip"
cp "$WORK/$NAME.dmg" "$WORK/$NAME.zip" release-assets/
(cd release-assets && shasum -a 256 "$NAME.dmg" "$NAME.zip" > "$NAME-SHA256SUMS.txt")
echo "Release assets: release-assets/$NAME.{dmg,zip}"
