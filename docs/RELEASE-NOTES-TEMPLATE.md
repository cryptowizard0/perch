<!--
Release notes for `gh release create vX.Y.Z --notes-file …`. Fill in the version and What's new; keep the
Install section as it is: every release says how to get past Gatekeeper and that Codex needs /hooks.
-->

## What's new

- …

## Install

Apple silicon, macOS 14+.

- **Homebrew:** `brew tap cryptowizard0/perch https://github.com/cryptowizard0/perch && brew install --cask perch` (already tapped: `brew upgrade --cask perch`).
- **Download:** `perch-X.Y.Z-macos-arm64.zip` below. Unzip it and drag `Perch.app` into Applications (`/Applications` or `~/Applications`). To upgrade, replace the old app.

Then:

1. **Open Perch past Gatekeeper (first install only).** Perch is ad-hoc signed, not notarized, so macOS blocks the first open. Click **Done**, then **System Settings → Privacy & Security → Open Anyway** next to Perch, and enter your password.
2. **Connect** your agents on the setup card in the notch (first install only). Nothing in an agent's config changes before you click it.
3. **Codex: trust the hooks with `/hooks`.** Codex skips new or changed hooks silently until you trust them: start `codex`, type `/hooks`, trust Perch's hooks, then open a new session. Needed after a first install, and after an upgrade when the notch shows *Trust Perch's hooks: run /hooks in codex*.

Check the download: `shasum -a 256 -c perch-X.Y.Z-macos-arm64.zip.sha256`.
