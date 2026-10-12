#!/bin/sh
# `perch` on PATH for a Homebrew install (the cask links Perch.app/Contents/Resources/bin/perch). Runs the perch that
# Perch.app copies into ~/.perch/bin on first open: the one every hook runs, without the quarantine flag that gets
# the bundled, unnotarized binary killed when run from a shell. A script is fine to run while quarantined.
# Always ~/.perch, never $PERCH_HOME: an app that maintains the install ignores PERCH_HOME too.
perch="$HOME/.perch/bin/perch"
[ -x "$perch" ] && exec "$perch" "$@"

# A constant with no " or \ in it, so it goes into the JSON as it is.
message="open Perch.app once to finish installing (it puts perch in ~/.perch/bin)"
for arg in "$@"; do
    if [ "$arg" = "--json" ]; then
        printf '{"ok":false,"error":"%s"}\n' "$message"
        exit 1
    fi
done
echo "perch: $message" >&2
exit 1
