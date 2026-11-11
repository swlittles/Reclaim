#!/bin/bash
# Native app packaging; adapted from Bustelo/Snippet (MIT), with isolated Dev identity.
set -euo pipefail
cd "$(dirname "$0")/.."
variant="${RECLAIM_BUILD_VARIANT:-development}"
case "$variant" in
  development) app_name='Reclaim Dev'; bundle_id='io.github.swlittles.Reclaim.dev' ;;
  production) app_name='Reclaim'; bundle_id='io.github.swlittles.Reclaim' ;;
  *) echo 'RECLAIM_BUILD_VARIANT must be development or production.' >&2; exit 1 ;;
esac
version=$(cat VERSION)
build=$(cat BUILD_NUMBER)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid version/build.' >&2; exit 1; }
key_file="${RECLAIM_SPARKLE_PUBLIC_KEY_FILE:-$PWD/Config/SparklePublicKey.txt}"
if [[ "$variant" = production ]]; then
  python3 - "$key_file" <<'PY'
import base64, pathlib, sys
p = pathlib.Path(sys.argv[1])
try:
    assert len(base64.b64decode(p.read_text().strip(), validate=True)) == 32
except Exception:
    sys.exit('Production requires a real Reclaim Ed25519 public key in Config/SparklePublicKey.txt (or RECLAIM_SPARKLE_PUBLIC_KEY_FILE). See docs/RELEASING.md.')
PY
fi
output="${RECLAIM_OUTPUT_DIR:-$PWD/dist}"
mkdir -p "$output"
output=$(cd "$output" && pwd)
if /bin/ps -axo comm= | /usr/bin/grep -Fxq "$output/$app_name.app/Contents/MacOS/$app_name"; then echo 'Quit the target app before rebuilding.' >&2; exit 1; fi
staging=$(mktemp -d "$output/.reclaim-build.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/$app_name.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
if [[ "${RECLAIM_UNIVERSAL:-0}" = 1 ]]; then
  for arch in arm64 x86_64; do swift build -c release --product Reclaim --triple "$arch-apple-macosx13.0" --scratch-path ".build/distribution-$arch"; done
  lipo -create .build/distribution-arm64/release/Reclaim .build/distribution-x86_64/release/Reclaim -output "$app/Contents/MacOS/$app_name"
  lipo "$app/Contents/MacOS/$app_name" -verify_arch arm64 x86_64
  framework=.build/distribution-arm64/release/Sparkle.framework
else
  swift build -c release --product Reclaim
  cp .build/release/Reclaim "$app/Contents/MacOS/$app_name"
  framework=.build/release/Sparkle.framework
fi
ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
identity="${RECLAIM_SIGNING_IDENTITY:--}"
sign_args=(--force --sign "$identity")
if [[ "$identity" != - ]]; then sign_args+=(--options runtime --timestamp); fi
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for component in "$sparkle/Autoupdate" "$sparkle/Updater.app" "$sparkle/XPCServices/Downloader.xpc" "$sparkle/XPCServices/Installer.xpc" "$app/Contents/Frameworks/Sparkle.framework"; do codesign "${sign_args[@]}" "$component"; done
if [[ "$variant" = development ]]; then
  swift scripts/make-icon.swift "$staging" --development
else
  swift scripts/make-icon.swift "$staging"
fi
iconutil -c icns "$staging/Reclaim.iconset" -o "$app/Contents/Resources/Reclaim.icns"
cp LICENSE docs/THIRD_PARTY_NOTICES.txt "$app/Contents/Resources/"
python3 - "$app/Contents/Info.plist" "$app_name" "$bundle_id" "$version" "$build" "$variant" "$key_file" <<'PY'
import pathlib, plistlib, sys
path, name, bundle, version, build, variant, key = sys.argv[1:]
p = dict(CFBundleExecutable=name, CFBundleIdentifier=bundle, CFBundleIconFile='Reclaim', CFBundleName=name, CFBundleDisplayName=name, CFBundlePackageType='APPL', CFBundleShortVersionString=version, CFBundleVersion=build, LSApplicationCategoryType='public.app-category.utilities', LSMinimumSystemVersion='13.0', LSUIElement=True, NSHighResolutionCapable=True, NSHumanReadableCopyright='© 2026 Stephen Little. MIT License.')
if variant == 'production':
    p.update(SUFeedURL='https://github.com/swlittles/Reclaim/releases/latest/download/appcast.xml', SUPublicEDKey=pathlib.Path(key).read_text().strip(), SUEnableAutomaticChecks=True, SUScheduledCheckInterval=86400, SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=False, SUEnableSystemProfiling=False, SUVerifyUpdateBeforeExtraction=True, SURequireSignedFeed=True)
with open(path, 'wb') as f: plistlib.dump(p, f)
PY
codesign "${sign_args[@]}" "$app"
codesign --verify --deep --strict "$app"
if /bin/ps -axo comm= | /usr/bin/grep -Fxq "$output/$app_name.app/Contents/MacOS/$app_name"; then echo "Target app opened during build; quit it before retrying." >&2; exit 1; fi
rm -rf "$output/$app_name.app"
mv "$app" "$output/$app_name.app"
python3 scripts/validate-bundle.py "$output/$app_name.app" "$variant"
echo "Built $output/$app_name.app"
