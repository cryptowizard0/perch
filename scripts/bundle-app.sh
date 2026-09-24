#!/bin/sh
# Builds the notch app with SwiftPM and assembles Perch.app — no Xcode needed.
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

swift build -c "$CONFIG" --product PerchApp
BIN=$(swift build -c "$CONFIG" --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PerchApp" "$APP/Contents/MacOS/Perch"
sed "s/__VERSION__/$SHORT/g" packaging/Info.plist > "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "$APP"
