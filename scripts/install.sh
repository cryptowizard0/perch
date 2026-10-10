#!/bin/sh
# Installs Perch for daily use from this checkout. Running it is consent to connect your agents, as before:
#   `perch setup` from the build output copies perch + perchd into ~/.perch/bin (the fixed location every hook
#   and the launchd agent run), installs perchd as a launchd agent, and connects every agent set up on this Mac
#   (Claude Code, Codex) that you haven't disconnected with `perch hooks uninstall <agent>`. It also migrates a
#   v0.3 install (binaries and hooks in ~/.local/bin).
#   perch / perchd are linked into $PREFIX (default ~/.local/bin) for typing; Perch.app → $APPDIR (default ~/Applications).
#   Hermes is not supported for now (2026-10-08): `perch hooks install hermes` still puts its hooks back by hand.
# Re-run after pulling to upgrade. Undo: perch uninstall (--purge also removes ~/.perch); rm -rf $APPDIR/Perch.app
set -eu
cd "$(dirname "$0")/.."
PREFIX=${PREFIX:-$HOME/.local/bin}
APPDIR=${APPDIR:-$HOME/Applications}

swift build -c release
BIN=$(swift build -c release --show-bin-path)
"$BIN/perch" setup

INSTALLED=${PERCH_HOME:-$HOME/.perch}/bin
mkdir -p "$PREFIX" "$APPDIR"
for name in perch perchd; do
    if [ -e "$PREFIX/$name" ] && [ ! -L "$PREFIX/$name" ]; then
        echo "$PREFIX/$name is not Perch's link; left it alone" >&2
    else
        ln -sfn "$INSTALLED/$name" "$PREFIX/$name"
    fi
done
echo "linked perch, perchd → $PREFIX"

osascript -e 'quit app id "dev.perch.app"' >/dev/null 2>&1 || true
APP="$APPDIR/Perch.app" scripts/bundle-app.sh >/dev/null
echo "installed Perch.app → $APPDIR"
open "$APPDIR/Perch.app"
