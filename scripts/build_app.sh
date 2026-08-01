#!/bin/bash
# Builds MViewer.app (release) into build/, injecting the version from VERSION.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
swift build -c release

APP=build/MViewer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MViewer "$APP/Contents/MacOS/MViewer"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" >/dev/null 2>&1

echo "Built $APP (v$VERSION)"
