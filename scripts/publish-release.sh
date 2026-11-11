#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${RELEASE_TAG:?Set the tested version tag}"
version=$(cat VERSION)
[[ "$RELEASE_TAG" = "v$version" ]] || { echo 'Tag/version mismatch.' >&2; exit 1; }
git rev-parse --verify "refs/tags/$RELEASE_TAG" >/dev/null
python3 scripts/validate-version.py
name="Reclaim-$version-macos-universal"
assets=("release-assets/$name.dmg" "release-assets/$name.zip" "release-assets/$name-SHA256SUMS.txt" release-assets/appcast.xml)
for asset in "${assets[@]}"; do [[ -f "$asset" ]] || { echo "Missing verified asset: $asset" >&2; exit 1; }; done
(cd release-assets && shasum -a 256 -c "$name-SHA256SUMS.txt")
bash scripts/release-notes.sh > release-assets/NOTES.md
if draft=$(gh release view "$RELEASE_TAG" --json isDraft --jq .isDraft 2>/dev/null); then
    [[ "$draft" = true ]] || { echo 'Release is already published; refusing to replace assets.' >&2; exit 1; }
    gh release upload "$RELEASE_TAG" "${assets[@]}" --clobber
    gh release edit "$RELEASE_TAG" --title "Reclaim $RELEASE_TAG" --notes-file release-assets/NOTES.md --draft=false --latest
else
    gh release create "$RELEASE_TAG" "${assets[@]}" --verify-tag --title "Reclaim $RELEASE_TAG" --notes-file release-assets/NOTES.md --latest
fi
