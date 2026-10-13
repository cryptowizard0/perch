#!/bin/sh
# Regenerates Perch's chimes (scripts/sound/make-sounds.swift) into packaging/sounds/, which scripts/bundle-app.sh
# copies into Perch.app. Run it after changing the synthesis; commit the .wav files.
set -eu
cd "$(dirname "$0")/../.."
swift scripts/sound/make-sounds.swift packaging/sounds
