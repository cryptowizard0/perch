# Perch

**Your AI coding agents, live in the MacBook notch.** See at a glance which session is running, which one needs you, and which one finished or failed. Approve safe commands right there, or click to jump back to the right terminal.

<p align="center"><img src="docs/images/desktop-expanded.png" alt="A Mac desktop with Perch's panel hanging from the notch: sessions grouped into Needs you, Failed, Running, Done and Idle"></p>

The loop it is built for: **an agent is waiting for you → the notch lights up → you handle it in place, or jump back.**

- **One row per agent session**, in five states: 🟠 Needs you · 🔴 Failed · 🟢 Running · 🔵 Done · ⚪ Idle.
- **A pixel cyclops lives in the notch** and acts out the most urgent state: it trots while an agent runs, waves at you when one needs you, and hops when one starts needing you, fails or finishes.
- **Allow / Deny in the notch** for commands on your allowlist (`npm test`, `git status`, …). Everything else shows the full command and *Answer in the terminal*.
- **Click a row** to go back to its terminal (the exact Ghostty tab) or its desktop app.
- Works with **Claude Code** and **Codex**, in the terminal or their desktop apps, through their hooks. No changes to how you run them.

macOS 14+. Prebuilt for Apple silicon; builds from source on any Mac. On displays without a notch it sits in a small capsule at the top of the screen.

## Install

Apple silicon, macOS 14+. Install the app, open it once past Gatekeeper, and click **Connect** in the notch.

**Homebrew**, from Perch's own tap (this repository):

```bash
brew tap cryptowizard0/perch https://github.com/cryptowizard0/perch
brew install --cask perch
```

**Or download** `perch-<version>-macos-arm64.zip` from the [latest release](https://github.com/cryptowizard0/perch/releases/latest), unzip it, and drag `Perch.app` into Applications. It has to be in `/Applications` or `~/Applications`: opened from Downloads, Perch shows no setup.

### 1. Open it past Gatekeeper (once)

Perch is ad-hoc signed, not notarized, so macOS blocks the first open ("Apple could not verify “Perch”…"). Click **Done**, then open **System Settings → Privacy & Security**, scroll to **Security** and click **Open Anyway** next to Perch (the button stays for about an hour after the blocked open), and enter your password. From then on Perch opens normally.

### 2. Connect your agents

On the first open the notch opens by itself with a setup card listing the agents it found: Claude Code if `~/.claude` exists, Codex if `~/.codex` does (`$CLAUDE_CONFIG_DIR` / `$CODEX_HOME` are honoured). Click **Connect**: Perch adds its hooks to their settings, only its own, after backing the file up as `.perch-backup`. **Open at login** is checked by default. Nothing in an agent's config changes before you click Connect.

Behind the scenes the app copies `perch` and `perchd` into `~/.perch/bin`, the fixed location every hook runs, and installs `perchd` as a launchd agent. Your choices are kept in `~/.perch/agents.json`. An agent you install later shows up as *Codex found · Connect*; right-click the notch → **Agents** to connect or disconnect one.

### 3. Codex: trust the hooks (once)

**Codex skips new hooks silently until you trust them**, so until you do, Codex sessions never show up and the notch shows *Trust Perch's hooks: run /hooks in codex*. Start `codex`, type `/hooks`, trust Perch's six hooks (UserPromptSubmit, PermissionRequest, PostToolUse, Stop, Interrupt, SessionEnd), then open a new Codex session; the row goes away on its first event.

Codex remembers trust per hook content, so it asks again only when an upgrade changes Perch's hooks. Claude Code needs no such step.

### `perch` in the terminal

Homebrew puts `perch` on your `PATH`. Otherwise link it: `ln -s ~/.perch/bin/perch ~/.local/bin/perch` (any directory on your `PATH`). Open the app once first: `~/.perch/bin` appears then, and until macOS has let Perch open, nothing inside the app runs.

### Upgrade

Replace the app: `brew upgrade --cask perch`, or drag the new `Perch.app` over the old one. On launch it copies its `perch` / `perchd` into `~/.perch/bin`, restarts `perchd` and updates Perch's hooks. A v0.3 install (binaries and hooks in `~/.local/bin`) is migrated the same way; Codex asks for trust once more.

### Uninstall

Right-click the notch → **Uninstall Perch…**. It removes Perch's hooks from every agent, stops `perchd` and removes its launchd agent and `~/.perch/bin`, turns off Open at login and moves the app to the Trash. `~/.perch` keeps the database, `allowlist.json` and `agents.json`, so a reinstall picks up where you left off.

With Homebrew, use `brew uninstall --cask perch` instead (the same removal); `brew uninstall --cask --zap perch` also deletes `~/.perch`. From a terminal: `perch uninstall` (`--purge` also deletes `~/.perch`), then delete the app.

### From source

Needs a Swift 5.9+ toolchain: Xcode or just the Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/cryptowizard0/perch.git && cd perch
scripts/install.sh
```

It builds `Perch.app` into `~/Applications` (`APPDIR=/Applications` also works) and opens it: the same first run as above, without the Gatekeeper step. It links `perch` / `perchd` into `~/.local/bin` (`PREFIX=…`). Re-run it after pulling to upgrade: a development build keeps its version number, so the script also runs the bundled `perch setup --upgrade`, which copies the new binaries, restarts `perchd` and repairs the hooks of connected agents, and connects nothing new.

## Use

| | |
| --- | --- |
| Hover the notch | Expand the panel |
| Click a row | Jump to that session's terminal or app; a Done session turns Idle |
| **Allow** / **Deny**, or ⌥⇧A / ⌥⇧D | Answer the first request in the panel |
| ⌥⇧O | Jump to the session that has waited longest |
| Right-click a row | *Remove from Panel* (its next event brings it back) |

The shortcuts exist only while there is something to answer or jump to, so the rest of the time those keys type as usual.

```bash
perch session ls                       # what the panel shows, in the terminal
perch allowlist                        # what may be approved from the notch
perch allowlist check Bash "npm test"  # would this be?
perch allowlist init                   # write ~/.perch/allowlist.json to edit
```

## Safety

- **Perch never allows anything by default.** If you don't answer in the notch within 20 seconds, the agent's own prompt appears in the terminal as usual.
- Only commands on the allowlist get buttons. The default is strict: read-only tools (Read, Glob, Grep, WebFetch, WebSearch) and a few Bash commands (`npm test`, `pytest`, `cargo test`, `git status` / `diff` / `log`). Any shell operator (`;`, `|`, `>`, `$(…)`, …), `rm`, `sudo`, and writes to `.env`, `~/.ssh` or `*.pem` always go to the terminal. A broken allowlist file approves nothing.
- The panel always shows the full command, never a summary.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| "Apple could not verify “Perch”…" | Expected once: **Open Anyway** in System Settings → Privacy & Security (see [Install](#1-open-it-past-gatekeeper-once)). |
| No setup card, no setup rows, no Agents menu | The app must run from `/Applications` or `~/Applications` (macOS runs apps opened from Downloads from a hidden copy), with `PERCH_HOME` unset. The card itself appears only on the first run; afterwards use the *found · Connect* rows or right-click → **Agents**. |
| Codex sessions never appear | The hooks are not trusted yet: `/hooks` in `codex` (see [Codex](#3-codex-trust-the-hooks-once)). `grep -A1 'hooks.json:permission_request' ~/.codex/config.toml` shows a `trusted_hash` once they are. |
| Claude Code sessions never appear | Claude Code needs no trust step and picks up new hooks on its own. Type `/hooks` in `claude`: Perch's eight hooks should be listed under user settings. If not, check for `"disableAllHooks": true` in any settings file (a project's settings override yours), `allowManagedHooksOnly` in managed settings on a work machine, and that Perch connected the settings file Claude Code reads (the card shows the path; `CLAUDE_CONFIG_DIR` must match). |
| No session appears for any agent | An error row in the notch says what failed. `perch session ls` must list sessions; if it cannot connect, `perchd` is not running: quit Perch and open it again (it reinstalls the launchd agent if it is gone), or run `perch setup`. |
| `perch: open Perch.app once to finish installing` | Homebrew's `perch` runs `~/.perch/bin/perch`, which the app installs on its first open. |
| The notch doesn't come back after a restart | Right-click the notch → **Open at Login**; if it says *allow in System Settings*, turn Perch on under System Settings → General → Login Items. |
| A hook fails | Hooks never print anything or block the agent; failures go to `~/.perch/hook.log`. No such file usually means the hook was never run at all. |

## How it works

```
Claude Code / Codex ──hook──▶ perch hook ──▶ perchd ──events──▶ Perch.app (notch)
                                             SQLite, ~/.perch/perchd.sock
```

- `perch` is the CLI and the hook adapter. It reports each hook event (prompt, needs you, done, failed, …) as a session update.
- `perchd` is the daemon and the only thing that touches the database. It runs the session state machine and pushes changes to the app, never polled: CLI to notch averages about 15 ms (budget 200 ms).
- `Perch.app` is the notch panel (AppKit + SwiftUI).

`perch watch --json` streams the same events, one JSON object per line. Every command takes `--json`; `perch --help` lists them all (the todo commands `add` / `ls` / `done` are still there, though the notch shows only agent sessions for now).

## Develop

No Xcode project: everything is SwiftPM.

```bash
swift build && swift test                              # CLI, daemon, libraries, tests
scripts/bundle-app.sh && open .build/Perch.app          # the notch app (CONFIG=debug for a debug build)
PERCH_HOME=/tmp/perch-dev swift run perchd --no-http    # a daemon with its own data, away from ~/.perch
scripts/measure-latency.sh                              # CLI → notch latency
```

Design notes (in Chinese): [docs/PRD.md](docs/PRD.md) (product), [docs/MILESTONES.md](docs/MILESTONES.md), [project.md](project.md) (status and handover), [CLAUDE.md](CLAUDE.md) (architecture rules).

## Screenshots

Collapsed, the notch shows the mascot acting out the most urgent session's state, and how many sessions are running:

<p align="center"><img src="docs/images/desktop-collapsed.png" alt="The menu bar with Perch collapsed around the notch: an orange pixel cyclops waving on the left, next to the number of running sessions"></p>

<p align="center"><img src="docs/images/mascot-states.png" width="552" alt="The mascot close up, one per state: green Running, orange Needs you, red Failed with an X in its eye, blue Done smiling, grey Idle asleep with a z, dark grey with no sessions"></p>

Running trots and looks around, Needs you waves and flashes its antenna, Failed and Done stand still, Idle sleeps. It moves only when it has something to say, and stays still with Reduce Motion on.

Expanded on hover, sessions are grouped by state, most urgent first:

<p align="center"><img src="docs/images/panel-expanded.png" width="460" alt="Perch's expanded panel, close up"></p>

Each row shows the agent (Claude Code's pixel monster, Codex's knot), the project, how long it has been in that state, and a second line: the prompt while running, the full command when it needs you, the error when it failed, the last reply when done.

## License

[MIT](LICENSE)
