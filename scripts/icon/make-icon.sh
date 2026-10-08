#!/bin/sh
# Redraws Perch's app icon (scripts/icon/draw-icon.swift) and packs it into packaging/Perch.icns,
# which scripts/bundle-app.sh copies into Perch.app. Run it after changing the drawing; commit the .icns.
set -eu
cd "$(dirname "$0")/../.."
ICONSET=$(mktemp -d /tmp/perch-icon.XXXXXX)/Perch.iconset
swift scripts/icon/draw-icon.swift "$ICONSET"
iconutil -c icns -o packaging/Perch.icns "$ICONSET"
rm -rf "$(dirname "$ICONSET")"
echo "packaging/Perch.icns"
