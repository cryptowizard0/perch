# Perch — CLAUDE.md

Perch（栖）：住在 MacBook 刘海里的 agent 等待队列，顺带是我的待办。
核心闭环只有一个：**agent 在等你 → 刘海亮 → 你就地处理或跳回去。**
产品需求见 `docs/PRD.md`，里程碑与验收标准见 `docs/MILESTONES.md`，**当前进度、下一步计划和交接说明见 `project.md`（新 session 先读它）**。先自用，但按可开源分发的形态设计。

## 仓库结构

```
Package.swift            SwiftPM：PerchCore（库）、perch（CLI）、perchd（daemon）、PerchApp（刘海 App）
Sources/PerchCore/       模型、wire protocol、路径、纯解析/渲染。所有客户端共享，不含任何 I/O
Sources/PerchClient/     Unix socket 客户端（CLI 和刘海 App 共用）
Sources/PerchDaemon/     daemon 的全部逻辑（库，便于测试）：SQLite、请求处理、socket/HTTP、文件镜像、launchd
Sources/CSQLite/         系统 libsqlite3 的最小声明（见下方 SQLite 决定）
Sources/perch/           CLI，唯一对外契约（ArgumentParser）
Sources/perchd/          daemon 可执行文件入口，只做组装
Tests/PerchCoreTests/    swift-testing（`import Testing`；只装 Command Line Tools 也能跑，XCTest 需要完整 Xcode）
Sources/PerchApp/        刘海 App（AppKit + SwiftUI），SwiftPM 可执行 target，不需要 Xcode
packaging/Info.plist     Perch.app 的 Info.plist（LSUIElement，无 Dock 图标）
scripts/bundle-app.sh    编译 PerchApp 并组装、ad-hoc 签名成 .build/Perch.app
docs/                    PRD、里程碑、给其他 agent 用的 SKILL 片段
hooks/                   （M3 起）Claude Code / Codex 的 hook 适配脚本
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
```

## 不可动摇的架构决定

1. **daemon 是唯一真相。** 只有 `perchd` 打开 SQLite。CLI、刘海 App、Hermes 全是客户端，谁都不直接碰数据库。
2. **CLI 是唯一契约。** 任何能跑 shell 的 agent 零学习成本接入；存储格式可以随时换，CLI 参数不能随便改。全部子命令支持 `--json`；`add --key` 幂等。
3. **推事件，不轮询。** daemon 通过 socket 广播 `Event`，刘海 UI 订阅。CLI 调用到刘海更新 ≤ 200 ms。
4. **传输层。** Unix socket `~/.perch/perchd.sock`（本机），加 `127.0.0.1:7331` HTTP（给 Docker 里的 Hermes，`host.docker.internal:7331`）。两者跑同一套 JSON（`Sources/PerchCore/Protocol.swift`）：socket 上是 newline-delimited JSON，HTTP 上是 `POST /rpc`；`watch` 保持连接并逐行推送带 `event` 的 `Response`。
5. **文件是单向的。** `~/.perch/todo.md` 是 daemon 渲染的只读镜像；`~/.perch/inbox.md` 是追加式收件箱，daemon 监听到 `- [ ] …` 就吸收进库并清空。**没有双向同步，永远不要实现。**
6. **刘海只是快捷通道，不是唯一通道。** hook 等刘海响应 15–30 秒，超时不返回决定，终端原生提示照常弹出。任何情况下都不会因为 Perch 而默认放行。
7. **一种语言。** 全部 Swift 5.9 / macOS 14+。daemon 和 CLI 打成单二进制。

## 数据模型

一张 `items` 表，字段与 `Item`（`Sources/PerchCore/Models.swift`）一一对应，JSON 用 snake_case，日期 ISO-8601：
`id`（4 位可手打，如 `t7k2`）、`title`、`kind`（task / notice / request）、`status`（open / waiting / done / dismissed）、`source`（自由字符串）、`due_at`、`link`、`meta`、`key`、request 专用的 `options` / `response` / `expires_at`、`created_at` / `updated_at`。
`kind` 区分 task 和 notice 是刻意的："agent 完成了"不是待办，混在一起会稀释橙色信号。

## Hook 适配（M3 / M4 / M5）

两家的 hook 事件名、stdin JSON 结构和 600 秒默认超时一致，共用一套脚本，只在返回格式处分支。

| 事件 | 适配器行为 | 阻塞 agent |
| --- | --- | --- |
| `SessionStart` / `Stop` | 维护 Live Activity：哪些 agent 在跑、跑了多久 | 否 |
| `Notification`（matcher `permission_prompt` / `idle_prompt` / `agent_needs_input`） | `perch add --status waiting --key <session_id>` | 否 |
| `Stop` | resolve 同 key 的 waiting，发一条 notice（含 `last_assistant_message` 摘要） | 否 |
| `PermissionRequest` | `perch add --kind request --wait`，拿到 allow/deny 后按各家格式打印 JSON | 是 |

`perch add --kind request --wait` 的约定：有人回应 → stdout 打印回应值、exit 0；过期（`--expires`）/ 被 done / 被 rm → exit 3、不打印回应。适配器只在 exit 0 时返回决定，其余一律不返回，让终端原生提示接管。

返回格式：Claude Code 是 `{"decision":"allow"|"deny","decisionReason":"…"}`（注意：不是 PreToolUse 的 `permissionDecision`，且 exit code 2 在 PermissionRequest 不生效）；Codex 是 decision 对象里的 `"behavior":"allow"|"deny"`。
配置文件：Claude Code `~/.claude/settings.json`；Codex `~/.codex/hooks.json`（首次运行需在终端确认信任）。
以官方文档为准：https://code.claude.com/docs/en/hooks 、 https://learn.chatgpt.com/docs/hooks 。

## 安全规则（M4 必须实现，不可绕过）

- 展开态必须显示完整命令原文，不截断不摘要。
- 白名单之外的工具不给批准按钮，只显示"去终端"。默认白名单：Read / Glob / Grep / WebFetch / WebSearch；Bash 只放 `npm test`、`pytest`、`cargo test`、`git status|diff|log`。`rm`、`sudo`、`git push --force`、`curl | sh`、写 `.env` / `~/.ssh` / `*.pem` 一律去终端。
- 白名单是本地配置文件，用户可改；默认值宁严勿松。

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

- `link` 跳回终端的机制：取决于日常用的终端（Zed 内置终端、Warp、tmux、iTerm 的 URL scheme 各不相同）。M3 前定。
- 全局快捷键默认值（快速录入；⌥⇧A / ⌥⇧D 批准 / 拒绝队首请求；⌥⇧O 跳转）。
- hook 等刘海的超时取 15 还是 30 秒，用一周后定。
- 开源许可证。
