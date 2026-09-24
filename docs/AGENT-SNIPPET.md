# 给其他项目的 agent 用的片段

把下面这段塞进目标项目的 `AGENTS.md` / `CLAUDE.md`，agent 就能主动使用 Perch（被动的 hook 接入不需要这段）。

```markdown
## Perch（人机共享任务面板）
- 需要人做决定或提供东西时：`perch add "<一句话说清要什么>" --source <你的名字> --status waiting --key <session_id> --link <当前目录或 PR 链接>`
- 做完一件值得告知的事：`perch add "<结果>" --kind notice --source <你的名字>`
- 查看人给你留的任务：`perch ls --source human --json`
- 完成一项：`perch done <id>`
- 同一件事不要重复 add，用同一个 `--key`。
```
