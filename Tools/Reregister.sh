#!/bin/bash
# Re-register WallePDFReader.app with LaunchServices.
# Run this after rebuilding the .app if Finder's "Open With" menu loses it.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/WallePDFReader.app"

LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

echo "→ Unregister old entry"
"$LSREG" -u "$APP" || true
echo "→ Register fresh"
"$LSREG" -f -trusted "$APP"
echo "→ Set as default PDF handler"
swift Tools/SetDefault.swift
echo "→ Restart Finder"
killall Finder || true
echo "✓ Done. Try double-clicking a PDF."
