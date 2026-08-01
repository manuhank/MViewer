#!/bin/bash
# Builds MViewer.app, packages it as a drag-to-Applications DMG in dist/,
# and publishes a GitHub release for the version in VERSION.
# Release notes are taken from the matching CHANGELOG.md entry.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
./scripts/build_app.sh

mkdir -p dist
STAGE=$(mktemp -d)
cp -R build/MViewer.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="dist/MViewer-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "MViewer" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Created $DMG"

# Extract this version's entry from CHANGELOG.md as the release notes.
NOTES=$(awk -v v="$VERSION" '
    $0 ~ "^## \\[" v "\\]" {found=1; next}
    /^## \[/ {found=0}
    found' CHANGELOG.md)

gh release create "v$VERSION" "$DMG" \
    --title "MViewer $VERSION" \
    --notes "$NOTES"
echo "Released v$VERSION."
