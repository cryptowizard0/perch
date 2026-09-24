# Perch

**Where your agents wait.** A MacBook-notch queue for AI coding agents — Claude Code, Codex, and your own.

When an agent needs permission, input, or just finished, Perch lights up the notch. Hover to see what it wants; allow or deny whitelisted actions in place; jump back to the terminal for anything else. A small todo list lives underneath.

- `perch` — the CLI, the only contract agents use (`perch add`, `perch ls`, `perch respond`, `perch watch`)
- `perchd` — the daemon: SQLite, Unix socket, localhost HTTP, event push
- `PerchApp` — the notch UI

Status: pre-alpha, milestone 1. See `docs/PRD.md` (中文) and `docs/MILESTONES.md`.

```
swift build && swift test
brew install xcodegen && xcodegen generate   # notch app project
```
