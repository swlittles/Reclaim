#!/bin/bash
set -euo pipefail
app="${1:?App required}"; destination="${2:?Destination required}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ditto "$app" "$work/Reclaim.app"
ln -s /Applications "$work/Applications"
hdiutil create -volname Reclaim -srcfolder "$work" -format UDZO "$destination" >/dev/null
hdiutil verify "$destination" >/dev/null
codesign --verify --deep --strict "$work/Reclaim.app"
