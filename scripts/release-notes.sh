#!/bin/bash
# Print the CHANGELOG.md section for VERSION (used for GitHub and in-app release notes).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
notes=$(awk -v heading="## $VERSION" '$0 == heading { found = 1; next } found && /^## / { exit } found' CHANGELOG.md)
[ -n "${notes//[[:space:]]/}" ] || { echo "CHANGELOG.md has no section for $VERSION." >&2; exit 1; }
printf '%s\n' "$notes"
