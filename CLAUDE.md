# Perch — CLAUDE.md

Perch（栖）：住在 MacBook 刘海里的 agent 灵动岛面板——一眼看到每个 agent 会话在跑、在等你、跑完了还是出错了。
核心闭环：**agent 在等你 → 刘海亮 → 你就地处理或跳回去。**
产品需求见 `docs/PRD.md`，里程碑与验收标准见 `docs/MILESTONES.md`，**当前进度、下一步计划和交接说明见 `project.md`（新 session 先读它）**。先自用，但按可开源分发的形态设计。

**2026-09-28 方向调整（v0.2）**：todo 暂时从刘海 UI 拿掉（底层和 CLI 不动，以后作为独立 tab 回来）；刘海只显示 agent 会话，一行一个会话，五种状态 Needs you 🟠 / Failed 🔴 / Running 🟢（呼吸）/ Done 🔵 / Idle ⚪。会话从 M7 起进 SQLite（`sessions` 表，状态机已实现，#15）。完整设计见 `docs/PRD.md` 的"v0.2 方向调整"和"Agent 面板"。下面凡标"（M8 前）"的描述是过渡期现状，M8 会改。

## 仓库结构

```
Package.swift            SwiftPM：PerchCore（库）、perch（CLI）、perchd（daemon）、PerchApp（刘海 App）
Sources/PerchCore/       模型、wire protocol、路径、纯解析/渲染。所有客户端共享，不含任何 I/O
Sources/PerchClient/     Unix socket 客户端（CLI 和刘海 App 共用）；sysctl 读进程（hook 找 agent、perchd 存活检测）
Sources/PerchAppCore/    刘海 App 的可测逻辑（库，不含 AppKit）：几何、队列状态、提醒、快捷键解析、连接 perchd
Sources/PerchDaemon/     daemon 的全部逻辑（库，便于测试）：SQLite、请求处理、socket/HTTP、文件镜像、launchd
Sources/CSQLite/         系统 libsqlite3 的最小声明（见下方 SQLite 决定）
Sources/perch/           CLI，唯一对外契约（ArgumentParser）
Sources/perchd/          daemon 可执行文件入口，只做组装
Tests/PerchCoreTests/    swift-testing（`import Testing`；只装 Command Line Tools 也能跑，XCTest 需要完整 Xcode）
Sources/PerchApp/        刘海 App（AppKit + SwiftUI），SwiftPM 可执行 target，不需要 Xcode
packaging/Info.plist     Perch.app 的 Info.plist（LSUIElement，无 Dock 图标）
scripts/bundle-app.sh    编译 PerchApp 并组装、ad-hoc 签名成 .build/Perch.app
docs/                    PRD、里程碑、给其他 agent 用的 SKILL 片段
Sources/perch/Hook*.swift  hook 适配器就是 CLI 子命令：`perch hook <agent>`（读 stdin）、`perch hooks install|uninstall`
scripts/install.sh       日常安装：perch / perchd → ~/.local/bin，Perch.app → ~/Applications，launchd，hooks
```

## 常用命令

```
swift build                      # 编译 CLI + daemon + 库
swift test                       # 单元测试，每次提交前必须通过
swift run perch --help
swift run perchd                 # 前台跑 daemon（PERCH_HOME=/tmp/x 可隔离数据）
swift run perchd install         # 装成 launchd agent（--dry-run 只打印 plist）；perchd uninstall 移除
scripts/bundle-app.sh            # 打包刘海 App → .build/Perch.app（CONFIG=debug 出调试版）
open .build/Perch.app
scripts/measure-latency.sh       # M2 验收：隔离的 perchd + App，量 CLI → 刘海延迟
```

## 不可动摇的架构决定

1. **daemon 是唯一真相。** 只有 `perchd` 打开 SQLite。CLI、刘海 App、Hermes 全是客户端，谁都不直接碰数据库。
2. **CLI 是唯一契约。** 任何能跑 shell 的 agent 零学习成本接入；存储格式可以随时换，CLI 参数不能随便改。全部子命令支持 `--json`；`add --key` 幂等。
3. **推事件，不轮询。** daemon 通过 socket 广播 `Event`，刘海 UI 订阅。CLI 调用到刘海更新 ≤ 200 ms。
4. **传输层。** Unix socket `~/.perch/perchd.sock`（本机），加 `127.0.0.1:7331` HTTP（给跑在容器里、够不着 socket 的客户端，`host.docker.internal:7331`；本机的 Hermes 走 hook，见下）。两者跑同一套 JSON（`Sources/PerchCore/Protocol.swift`）：socket 上是 newline-delimited JSON，HTTP 上是 `POST /rpc`；`watch` 保持连接并逐行推送带 `event` 的 `Response`。
5. **文件是单向的。** `~/.perch/todo.md` 是 daemon 渲染的只读镜像；`~/.perch/inbox.md` 是追加式收件箱，daemon 监听到 `- [ ] …` 就吸收进库并清空。**没有双向同步，永远不要实现。**
6. **刘海只是快捷通道，不是唯一通道。** hook 等刘海响应 15–30 秒，超时不返回决定，终端原生提示照常弹出。任何情况下都不会因为 Perch 而默认放行。
7. **一种语言。** 全部 Swift 5.9 / macOS 14+。daemon 和 CLI 打成单二进制。

## 数据模型

一张 `items` 表，字段与 `Item`（`Sources/PerchCore/Models.swift`）一一对应，JSON 用 snake_case，日期 ISO-8601：
`id`（4 位可手打，如 `t7k2`）、`title`、`kind`（task / notice / request）、`status`（open / waiting / done / dismissed）、`source`（自由字符串）、`due_at`、`link`、`meta`、`key`、request 专用的 `options` / `response` / `expires_at`、`created_at` / `updated_at`。
`kind` 区分 task 和 notice 是刻意的："agent 完成了"不是待办，混在一起会稀释橙色信号。

M7 起有 `sessions` 表（schema v2，字段与 `Session`（`Sources/PerchCore/Sessions.swift`）一一对应）：会话状态只放这里，重启后原样恢复。hook 适配器发 `session_report`（`SessionReport`：prompt / waiting / resume / stop / failure / interrupt / end，与 agent 无关），状态机在 perchd 的 `SessionRegistry`：比该会话最后一次事件旧的报告丢弃（平局照收），被移除的会话 10 分钟内记着移除时间，旧事件不会让它复活；Done 10 分钟后变 Idle（`session_seen` 立刻变）；resume / stop / failure / interrupt / end 顺带把 `meta.session_id` 指向该会话的 request 关掉（不带回应）。白名单内的 PermissionRequest 仍发 request（经 `meta.session_id` 挂到会话）。M8（#19）起 Claude Code / Codex 的 hook 不再发 waiting / notice item，request 是它们唯一会建的 item。清理：pid 存活检测（30 秒，比对进程启动时间防复用）为主，拿不到 pid 的 24 小时无事件兜底，`perch session rm` 手动移除（#16）。`perch hook` 沿父进程链找 argv[0] 叫 `claude` / `codex` 的最近祖先（`AgentProcess`，纯函数；进程表由 `PerchClient/SystemProcesses.swift` 用 sysctl 读），每条 `session_report` 带上它的 pid 和启动时间。**按 argv[0] 认，不按内核进程名**：`~/.local/bin/claude` 是指向 `versions/2.1.x` 的符号链接，内核记的名字是 `2.1.x`。

## Hook 适配（M3 / M4 / M5）

两家的 stdin JSON 结构、返回格式和 600 秒默认超时一致，共用一个适配器：`perch hook <agent>`（Swift，不写 shell 脚本；映射逻辑在 `PerchCore/Hooks.swift` 的 `HookAdapter`）。事件集合不同（M5 核对）：Codex 没有 `Notification` / `StopFailure` / `PostToolUseFailure`（waiting 只来自 PermissionRequest），多一个 `Interrupt`（Esc 打断一轮，不会再有 Stop）；`SessionEnd` 在 Codex 里总是同步跑、最多 3 秒。`perch hooks install <agent>` 按各家的事件表写。
不阻塞的 hook 一律 `"async": true`（例外：Codex 的 `SessionEnd` 总是同步跑，装成同步、timeout 3；Codex 的 `Interrupt` 即使 async 也最多 3 秒）；适配器**不往 stdout 打任何东西**（SessionStart / UserPromptSubmit 的 stdout 会进模型上下文）、永远 exit 0，失败写 `~/.perch/hook.log`。

每个事件只发一条 `session_report` 更新会话状态（映射见 `HookAdapter` 的文档注释和 `docs/PRD.md`"Agent 面板"），会话是唯一的状态；唯一的 item 是白名单内 PermissionRequest 的 request。阻塞、不打 stdout、exit 0、超时交给终端这些规则不变。PermissionRequest 的 request 没有回应就结束（过期、被 done / rm、被会话事件关掉）一律把会话改成"完整命令 + Answer in the terminal"，因为没有决定就是终端在问。

| 事件 | 会话 | 阻塞 agent |
| --- | --- | --- |
| `UserPromptSubmit` | running（本轮 prompt 首行）；Ghostty 下记下当前聚焦的 terminal id | 否 |
| `Notification`（matcher `permission_prompt` / `elicitation_dialog` / `agent_needs_input`；**不接 `idle_prompt`**） | waiting（agent 的原话；`permission_prompt` 不覆盖已记下的命令） | 否 |
| `Stop` | done（`last_assistant_message` 首行） | 否 |
| `StopFailure` / `Interrupt`（Codex） / `SessionEnd` | failed（记 `error`）/ idle / 移除 | 否 |
| `PermissionRequest` | waiting（完整命令）。白名单内：发 request 等刘海（`--wait`，默认 20 秒），有回应就打印决定、会话回 running；超时或白名单外：会话写上"Answer in the terminal"，不打印任何东西，终端原生提示接管 | 是 |
| `PostToolUse` / `PostToolUseFailure` | running（工具跑了，说明权限已在终端处理） | 否 |

Hermes Agent（M6 定：它跑在本机，不在 Docker 里，所以走 shell hook 而不是 HTTP）：同一个适配器 `perch hook hermes`，事件名是 snake_case，细节在 stdin 的 `extra` 里。Hermes 的 shell hook **同步**执行（timeout 10），stdout 若是 JSON 会被解析（`pre_llm_call` 的 `context` 会进 LLM 上下文），所以同样什么都不打印。

| 事件 | 适配器行为 |
| --- | --- |
| `pre_llm_call` | session_start（标题：gateway 用平台名如 "Telegram"，CLI 用项目名）；resolve 上一条 notice；CLI 在 Ghostty 下记下聚焦的 terminal（gateway 一律没有终端链接） |
| `post_llm_call` | 发 notice（`assistant_response` 首行） |
| `on_session_end`（每轮结束都触发，含中断） | session_end |
| `pre_approval_request` | add waiting（完整命令 + Hermes 给的原因），key `hermes:<session_key>:<tool_call_id>`，15 分钟后过期兜底（Hermes 自己 60 s / 300 s 超时）；CLI 显示"Answer in the terminal"（跳到同目录那一轮的终端），gateway 显示"Answer in Telegram"等 |
| `post_approval_response`（回应或超时） | resolve 那条 waiting |

`platform: subagent`（委派的子 agent）和后台 skill / memory 复盘（和父会话共用 session_id，只能靠它固定的 prompt 结尾识别）的 `pre_llm_call` / `post_llm_call` 一律忽略。

Hermes 的审批 hook 只能观察，不能代答，所以刘海**永远不能批准 Hermes 的命令**，只能提示去哪里回答。审批 hook 带的是 gateway 的 `session_key`（CLI 里是 `default`，gateway 是 `agent:main:<platform>:…`），不是 session_id。

会话 CLI：`perch session ls [--json]`（状态和详情）、`perch session seen <id>`（done → idle）、`perch session rm <id>`（手动移除，之后再来事件会重新出现）；`perch session start|end` 保持旧含义（start = 新一轮 running，end = 移除），Hermes 还在用。`watch` 推 `session.updated`（每次变化）、`session.ended`（移除）和 `session.started`（新一轮开始，给老客户端）。刘海（M8，#18）只显示会话（Hermes 除外，M9）：收起态 = 最紧急会话的颜色 + Running 数；展开态按状态分组，逻辑在 `PerchAppCore/Panel.swift`（`Panel` / `SessionRow`），像素图标在 `PixelIcon.swift`。Live Activity（"2 agents · 4m"）已去掉。

`perch add --kind request --wait` 的约定：有人回应 → stdout 打印回应值、exit 0；过期（`--expires`）/ 被 done / 被 rm → exit 3、不打印回应。适配器只在 exit 0 时返回决定，其余一律不返回，让终端原生提示接管。

返回格式（M4 按官方文档核对过）：Claude Code 是 `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"|"deny","message":"…"}}}`（`message` 只用于 deny；不是 PreToolUse 的 `permissionDecision`；exit code 2 在 PermissionRequest 不生效）。Codex（M5 核对）读同一个 JSON，所以不分支；不要返回 `updatedInput` / `updatedPermissions` / `interrupt`（Codex 目前对这些 fail closed）。
PermissionRequest 在弹提示框**之前**触发；`Notification` 的 `permission_prompt` 要等提示框挂了约 6 秒才触发。
配置文件：Claude Code `~/.claude/settings.json`；Codex `~/.codex/hooks.json`（`$CODEX_HOME` 可覆盖；Codex 按 hook 内容的 hash 记信任，新装或改过的 hook 要在 codex 里 `/hooks` 确认后才会跑）；Hermes `~/.hermes/config.yaml` 的 `hooks:`（`$HERMES_HOME` 可覆盖；没有 YAML 库，Perch 在文件末尾写一段带标记的块；Hermes 用 yaml.dump 重写文件时标记会丢，所以只含 Perch 命令的 `hooks:` 段也认作 Perch 的；混了别人 hook 的 `hooks:` 段不动、安装拒绝；Hermes 对每个 (事件, 命令) 首次运行要确认，记在 `~/.hermes/shell-hooks-allowlist.json`，gateway 要 `hermes gateway restart` 才会加载）。
以官方文档为准：https://code.claude.com/docs/en/hooks 、 https://learn.chatgpt.com/docs/hooks 、Hermes 仓库的 `website/docs/user-guide/features/hooks.md`（Shell Hooks 一节）。

## 安全规则（M4 必须实现，不可绕过）

- 展开态必须显示完整命令原文，不截断不摘要。
- 白名单之外的工具不给批准按钮，只显示"去终端"。默认白名单：Read / Glob / Grep / WebFetch / WebSearch；Bash 只放 `npm test`、`pytest`、`cargo test`、`git status|diff|log`。`rm`、`sudo`、`git push --force`、`curl | sh`、写 `.env` / `~/.ssh` / `*.pem` 一律去终端。
- 白名单是本地配置文件，用户可改；默认值宁严勿松。已实现（M4）：`~/.perch/allowlist.json`（没有文件 = 默认值；文件坏了 = 什么都不能在刘海批准），`perch allowlist [show|check|init]`。Bash 带 shell 元字符（`; & | $ \` > < ( ) \` 换行）或危险参数（`--output` 等）一律去终端；受保护路径对所有工具生效。
- 白名单外的请求不会变成 request：hook 立刻返回（终端马上弹提示框），刘海里那个会话只显示完整命令和"Answer in the terminal"。刘海按钮只对 request 显示，所以不存在"白名单外却有 Allow 按钮"的路径。

## 范围守卫（不要做）

dispatch（从刘海派任务给 agent）、stop / cancel、reply（在刘海里回答 agent 提问）、MCP server、markdown 双向同步、音乐控制、系统 HUD、文件中转、项目 / 标签 / 子任务 / 重复任务、云同步、iPhone、日历、多用户。
遇到"顺手加一个"的冲动，先看 `docs/PRD.md` 的"不做，及原因"。

## 代码与提交约定

- `swift build` 和 `swift test` 必须通过再提交。新增行为先写测试。
- 一个里程碑拆成小步提交，Conventional Commits（`feat(daemon): …`、`feat(cli): …`、`feat(app): …`、`feat(hooks): …`）。
- 刘海窗口层可以借 NotchDo（MIT，https://notchdo.app/ ）的实现，保留版权头。`luifon/notch-widget` 的 `CGSSpace.swift` 是 MPL-2.0，可单文件引用并保留头。**不要复制 Boring Notch 的代码**（GPL-3.0，会把整个项目锁成 GPL）。
- 不要引入重依赖。允许：swift-argument-parser。
- **SQLite：直接用系统 libsqlite3，不用 GRDB**（M1 定）。只有一张表，包装层（`Sources/PerchDaemon/SQLite.swift`）不到 100 行，零依赖。不 `import SQLite3`，而是走 `CSQLite` target 自己声明用到的函数：机器上 `/usr/local/include/sqlite3.h` 这类野生头文件会和 SDK 的 SQLite3 模块冲突导致编译失败。要用新的 sqlite3 函数就往 `Sources/CSQLite/include/CSQLite.h` 里加声明。日期列存 ISO-8601 UTC 文本，`meta` / `options` 存 JSON 文本，schema 版本用 `PRAGMA user_version`。
- App 不沙盒、不上 App Store（Unix socket、launchd、写 hook 配置都需要）。签名和公证到产品化再说。
- 错误信息要能让 agent 看懂：CLI 失败时 stderr 一行人类可读，`--json` 时 stdout 输出 `{"ok":false,"error":"…"}`，exit code 非 0。

## 未决问题（定了就更新这里）

- ~~`link` 跳回终端的机制~~ 已定（M3）：`perch-terminal://<app>?id=&cwd=&bundle=`。Ghostty（≥ 1.3，AppleScript）在 UserPromptSubmit 时记下聚焦的 terminal id，跳转时 `focus` 那个 terminal，找不到按目录找，再不行激活 App；其他终端只激活 App（按 `__CFBundleIdentifier`）。
- ~~全局快捷键默认值~~ 已定（M2）：快速录入 ⌥⇧Space（`defaults write dev.perch.app QuickEntryHotKey "ctrl+opt+n"` 可改）；⌥⇧A / ⌥⇧D 批准 / 拒绝队首请求、⌥⇧O 跳转，M4 实现。M8 起快速录入随 todo UI 下线，⌥⇧A / D / O 保留（队首 = 排序最前的 Needs you 会话）。
- ~~Claude 桌面 App 里的会话能否沿父进程链找到 agent 的 pid~~ 已定（M7 实测）：能。桌面 App 每个会话一个 `claude` 进程（`Claude` → `disclaimer` → `claude`），会话进程退出就移除。Codex 桌面 App（ChatGPT.app）所有会话共用一个 `codex app-server` 进程，只有退出 App 才会按 pid 清掉。
- 全屏 App 下刘海面板是否可见：M8 核实。
- hook 等刘海的超时：先用 20 秒（M4 定，`perch hooks install claude-code --wait N` 可改），用一周后再看。
- 开源许可证。
