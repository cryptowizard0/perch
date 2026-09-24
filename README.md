# Perch

**Where your agents wait.** A MacBook-notch queue for AI coding agents — Claude Code, Codex, and your own.

When an agent needs permission, input, or just finished, Perch lights up the notch. Hover to see what it wants; allow or deny whitelisted actions in place; jump back to the terminal for anything else. A small todo list lives underneath.

- `perch` — the CLI, the only contract agents use (`perch add`, `perch ls`, `perch respond`, `perch watch`)
- `perchd` — the daemon: SQLite, Unix socket, localhost HTTP, event push
- `PerchApp` — the notch UI

Status: pre-alpha. Milestone 1 (daemon + CLI) is done; the notch UI is next. See `docs/PRD.md` (中文) and `docs/MILESTONES.md`.

```
swift build && swift test
swift run perchd                              # foreground; or `perchd install` for a launchd agent
brew install xcodegen && xcodegen generate   # notch app project
```

```
perch add "review PR #42" --source codex --link https://github.com/o/r/pull/42 --due @15:00
perch add "needs input" --status waiting --source claude-code --key "$SESSION_ID"   # same key → same item
perch add "npm test" --kind request --expires 30 --wait    # prints allow/deny, or exits 3 on timeout
perch ls                                                     # queue order: requests, waiting, overdue, today, …
perch respond t7k2 allow
perch done t7k2
perch watch --json                                           # one event per line
echo "- [ ] buy milk +2h" >> ~/.perch/inbox.md               # absorbed as a task
cat ~/.perch/todo.md                                         # read-only mirror
curl -s localhost:7331/rpc -H 'Content-Type: application/json' -d '{"op":"list"}'
```

Every command takes `--json`; failures print `{"ok":false,"error":"…"}` and exit non-zero.
