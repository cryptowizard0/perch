#!/bin/sh
# Packages a release from this checkout (run it in a worktree of the release tag): a release build of Perch.app,
# zipped alone as dist/perch-<version>-macos-arm64.zip (perch and perchd ride inside it), its .sha256, and
# Casks/perch.rb updated to that version and checksum. Commit the cask change on main after `gh release create`.
set -eu
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*string = "\(.*\)".*/\1/p' Sources/PerchCore/Version.swift)
[ -n "$VERSION" ] || { echo "package-release: no version in Sources/PerchCore/Version.swift" >&2; exit 1; }
case "$VERSION" in *-*) echo "package-release: $VERSION is a development version; release from the tag" >&2; exit 1 ;; esac
[ "$(uname -m)" = arm64 ] || { echo "package-release: the zip is named arm64; build it on Apple silicon" >&2; exit 1; }
NAME="perch-$VERSION-macos-arm64"

rm -rf dist && mkdir dist
APP="dist/Perch.app" scripts/bundle-app.sh >/dev/null
ditto -c -k --keepParent dist/Perch.app "dist/$NAME.zip"
rm -rf dist/Perch.app
SHA=$(shasum -a 256 "dist/$NAME.zip" | cut -d' ' -f1)
echo "$SHA  $NAME.zip" > "dist/$NAME.zip.sha256"

sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/perch.rb
grep -q "^  version \"$VERSION\"" Casks/perch.rb && grep -q "^  sha256 \"$SHA\"" Casks/perch.rb ||
    { echo "package-release: couldn't set version / sha256 in Casks/perch.rb" >&2; exit 1; }
echo "dist/$NAME.zip"
echo "dist/$NAME.zip.sha256"
echo "Casks/perch.rb → $VERSION ($SHA)"
