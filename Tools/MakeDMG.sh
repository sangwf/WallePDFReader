#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="WallePDFReader.app"

# Build the app first (so the DMG always reflects the latest source)
./build.sh

VERSION=$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0")
DMG="WallePDFReader-${VERSION}.dmg"
STAGING="Build/dmg-staging"

# Stage: app + symlink to /Applications for drag-to-install
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Create compressed read-only DMG
hdiutil create \
    -volname "WallePDFReader" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG" >/dev/null

rm -rf "$STAGING"

echo
echo "✓ $(ls -lh "$DMG" | awk '{print $9, "("$5")"}')"
