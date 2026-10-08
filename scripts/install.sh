#!/bin/sh
# Installs Perch for daily use from this checkout:
#   perch + perchd → $PREFIX (default ~/.local/bin), Perch.app → $APPDIR (default ~/Applications),
#   perchd as a launchd agent, Claude Code hooks in ~/.claude/settings.json and, if Codex is set up
#   (~/.codex or $CODEX_HOME exists), Codex hooks in hooks.json there (skip both with --no-hooks).
#   Hermes is not supported for now (2026-10-08), so its hooks are not installed; the adapter is still in
#   `perch`, and `perch hooks install hermes` puts them back by hand.
# Re-run after pulling to upgrade. Undo: perch hooks uninstall claude-code|codex; perchd uninstall;
#   rm $PREFIX/perch $PREFIX/perchd; rm -rf $APPDIR/Perch.app
set -eu
cd "$(dirname "$0")/.."
PREFIX=${PREFIX:-$HOME/.local/bin}
APPDIR=${APPDIR:-$HOME/Applications}
HOOKS=1
[ "${1:-}" = "--no-hooks" ] && HOOKS=

swift build -c release
BIN=$(swift build -c release --show-bin-path)
mkdir -p "$PREFIX" "$APPDIR"
install -m 755 "$BIN/perch" "$BIN/perchd" "$PREFIX/"
echo "installed perch, perchd → $PREFIX"

# Restart the agent so it runs the new binary.
"$PREFIX/perchd" uninstall >/dev/null 2>&1 || true
"$PREFIX/perchd" install

osascript -e 'quit app id "dev.perch.app"' >/dev/null 2>&1 || true
APP="$APPDIR/Perch.app" scripts/bundle-app.sh >/dev/null
echo "installed Perch.app → $APPDIR"

if [ -n "$HOOKS" ]; then
    "$PREFIX/perch" hooks install claude-code --binary "$PREFIX/perch"
    if [ -d "${CODEX_HOME:-$HOME/.codex}" ]; then
        "$PREFIX/perch" hooks install codex --binary "$PREFIX/perch"
    fi
fi
open "$APPDIR/Perch.app"
