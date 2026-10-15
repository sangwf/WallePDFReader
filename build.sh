#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="WallePDFReader.app"
rm -rf "$APP" PDFReader.app
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp Info.plist "$APP/Contents/Info.plist"

# Generate app icon if missing or out-of-date relative to the source script
if [ ! -f Build/AppIcon.icns ] || [ Tools/MakeIcon.swift -nt Build/AppIcon.icns ]; then
    echo "Generating app icon…"
    mkdir -p Build
    swift Tools/MakeIcon.swift
    iconutil -c icns Build/AppIcon.iconset -o Build/AppIcon.icns
fi
cp Build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc -O -parse-as-library \
    -target arm64-apple-macos13 \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/WallePDFReader"

# Ad-hoc sign so Gatekeeper lets it run locally
codesign --force --sign - "$APP" >/dev/null

# LaunchServices notices the bundle while it is still being assembled and
# records it as having no executable, which drops it from Finder's Open With
# menu. Register the finished bundle so that stale record is replaced.
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -f "$PWD/$APP" || true

echo "Built $APP"
