#!/bin/sh
# Builds the notch app with SwiftPM and assembles Perch.app — no Xcode needed. The app carries perch and perchd in
# Contents/Helpers: an app in /Applications or ~/Applications copies them into ~/.perch/bin when their version differs.
#   scripts/bundle-app.sh              # release build → .build/Perch.app
#   CONFIG=debug scripts/bundle-app.sh
#   APP=/Applications/Perch.app scripts/bundle-app.sh
# Not sandboxed, ad-hoc signed (codesign -s -). Real signing and notarization come with productization.
set -eu
cd "$(dirname "$0")/.."

CONFIG=${CONFIG:-release}
APP=${APP:-.build/Perch.app}
VERSION=$(sed -n 's/.*string = "\(.*\)".*/\1/p' Sources/PerchCore/Version.swift)
SHORT=${VERSION%%-*}  # CFBundle*Version must be numeric

for product in PerchApp perch perchd; do
    swift build -c "$CONFIG" --product "$product"
done
BIN=$(swift build -c "$CONFIG" --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$BIN/PerchApp" "$APP/Contents/MacOS/Perch"
# Not in Contents/MacOS: `perch` and `Perch` are the same name on a case-insensitive disk.
cp "$BIN/perch" "$BIN/perchd" "$APP/Contents/Helpers/"
cp packaging/Perch.icns "$APP/Contents/Resources/Perch.icns"  # redraw with scripts/icon/make-icon.sh
sed "s/__VERSION__/$SHORT/g" packaging/Info.plist > "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
# Nested code first, then the bundle (which seals it).
codesign --force --sign - "$APP/Contents/Helpers/perch" "$APP/Contents/Helpers/perchd"
codesign --force --sign - "$APP"

echo "$APP"
