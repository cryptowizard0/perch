# Perch — 开发路线与进度（交接文档）

> 给接手的 session：先读本文，再读 `CLAUDE.md`（架构铁律）、`docs/MILESTONES.md`（逐项验收清单）、`docs/PRD.md`（产品需求）。
> 本文负责"做到哪了、下一步怎么做、有哪些坑"；验收框以 `docs/MILESTONES.md` 为准，两边进度要同步更新。

最后更新：2026-09-24 · M1 完成，下一步 M2

## 总览

| # | 里程碑 | 状态 | 说明 |
| --- | --- | --- | --- |
| M1 | daemon + CLI + SQLite + watch | ✅ 完成 | 10 项全勾，73 个测试通过 |
| M2 | 刘海 UI | ⏭ 下一步 | 见下方"M2 开发计划" |
| M3 | Claude Code 被动接入（Notification / Stop / SessionStart） | ⬜ 未开始 | 依赖 M2 的 Live Activity 数据来源（见未决问题） |
| M4 | PermissionRequest + 白名单 | ⬜ 未开始 | CLI 侧 `--wait` 已就绪 |
| M5 | Codex 复用同一套 hook 脚本 | ⬜ 未开始 | |
| M6 | Hermes HTTP 接入 | ⬜ 未开始 | HTTP `POST /rpc` 已就绪，只剩容器内实测 |

## 开发环境（重要）

- **本机没有 Xcode，只有 Command Line Tools**（Swift 6.1.2，`Package.swift` 仍是 tools-version 5.9 / Swift 5 语言模式）。
  - 没有 XCTest → 测试全部用 **swift-testing**（`import Testing`、`@Test`、`#expect`）。
  - `xcodebuild` 不可用 → App 用 SwiftPM 编译、`scripts/bundle-app.sh` 组装 `.app`（M2.1 定）。
  - SwiftUI / AppKit 可用：已验证 CLT 能编译运行 `NSPanel` + `NSHostingView`，并读到刘海安全区高度 33pt。
  - `codesign` 可用（ad-hoc 签名 `codesign -s -`）。`actool`（Asset Catalog）不可用 → 图标用 png / icns。
- `/usr/local/include/sqlite3.h` 是一个手动装的野头文件，会让 `import SQLite3` 编译失败。所以 daemon 用 `Sources/CSQLite` 自己声明 sqlite3 函数；新增函数就加到 `Sources/CSQLite/include/CSQLite.h`。**不要删那个系统文件，也不要改回 `import SQLite3`。**
- GitHub 走 ssh 偶尔失败（ssh-agent 签名问题）；依赖已在 `.build` 缓存。不要随意加新依赖。

## 常用命令

```
swift build && swift test                     # 每次提交前必须通过
PERCH_HOME=/tmp/perch-dev swift run perchd    # 隔离数据跑 daemon，不碰 ~/.perch
PERCH_HOME=/tmp/perch-dev swift run perch ls
swift run perchd install --dry-run            # 看 launchd plist；install / uninstall 真装真卸
```

## 当前代码地图（M1 结束时）

```
Sources/PerchCore/     纯逻辑，无 I/O，App 可直接复用：
  Models.swift           Item / Event；宽松解码（只有 title 必填）；queueRank / queueOrdered（刘海排序就用它）
  Protocol.swift         Request / Response / Filter（含 all）；PerchJSON（ISO-8601、sortedKeys、不转义 /）
  DueParser.swift        @15:00 / +30m / +1h30m / ISO-8601
  Markdown.swift         MirrorRenderer（todo.md）、Inbox（inbox.md 解析）、QuickEntry（"标题 @15:00" → 标题 + due）
  Paths.swift            ~/.perch（PERCH_HOME 可覆盖）
Sources/PerchClient/   PerchClient.send / watch() → EventStream；BufferedSocket（阻塞式 socket + 读缓冲）
Sources/PerchDaemon/   Daemon（串行队列 + 订阅者 + 过期计时器 + 镜像 + inbox 监听）、Service（各 op）、Store（sqlite）、
                       Server / HTTPConnection（Unix socket + 127.0.0.1 HTTP）、Files（MirrorWriter / InboxWatcher）、LaunchAgent
Sources/perch/         CLI：add / ls / get / done / respond / rm / watch / hooks（hooks 是 M3 占位）
Sources/perchd/        入口：run（默认）/ install / uninstall
PerchApp/PerchApp.swift  仍是 M0 占位（MenuBarExtra），M2 替换
Tests/PerchCoreTests/    纯逻辑
Tests/PerchDaemonTests/  进程内起 daemon（Support.swift 的 TestDaemon）+ 跑真实 perch 二进制（CLITests / AcceptanceTests）
```

## 已定下的契约（M2+ 依赖，改之前先想清楚）

- Wire：Unix socket 上一行一个 JSON；HTTP `POST /rpc` 同一套 JSON。`watch` 先回 `{"ok":true}` 确认，再逐行推 `{"ok":true,"event":{…}}`。**确认之后发生的变化保证能收到**，所以客户端正确做法是：先 `watch()`，再 `list` 拿快照。
- op：`ping / add / list / get / done / respond / remove / update / watch`。`list` 默认只返回 open + waiting，已按队列顺序排好。
- `add --key`：同 key 更新原项（保留 id 和 created_at），会重新打开已关闭项并清空旧 response；内容完全相同的重复 add 不发事件。
- request：默认 status waiting、options `allow,deny`；`respond` 校验选项，回应后 status 变 done。
- `expires_at`：到点 daemon 把 open / waiting 项置为 dismissed 并推 `item.updated`（notice 自动消失、request 超时都靠它）。
- `perch add --kind request --wait`：有回应 exit 0 并打印回应；过期 / 被 done / 被 rm 都 exit 3。**exit 3 永远不等于放行。**
- CLI 错误：stderr 一行 `perch: …`；`--json` 时 stdout 为 `{"ok":false,"error":"…"}`；exit 非 0（参数错误 64）。
- HTTP 拒绝带 `Origin` 头、非 `application/json`、Host 不在白名单（127.0.0.1 / localhost / [::1] / host.docker.internal）的请求。
- 文件：`todo.md` 只读（0444），内容变了才重写；`inbox.md` 启动时创建，只吸收 `- [ ]` / `* [ ]` 行，其余内容保留。

## M2 开发计划（刘海 UI）

按 `docs/MILESTONES.md` 的 M2 清单逐项做，每项一个 commit，做完勾框并更新本文进度表。

| # | 任务 | 状态 | 要点 |
| --- | --- | --- | --- |
| 2.1 | App 可编译运行、无 Dock 图标 | ✅ | `scripts/bundle-app.sh` → `.build/Perch.app`；`lsappinfo` 显示 type="UIElement" |
| 2.2 | NSPanel 贴刘海；无刘海退化为顶部居中胶囊 | ✅ | `NSScreen.safeAreaInsets.top > 0` 判断有无刘海；`auxiliaryTopLeftArea/RightArea` 算刘海宽度；多屏、换屏要跟着走 |
| 2.3 | 收起态：数字、颜色点、Live Activity | ✅ | 颜色：灰=空 / 蓝=有待办 / 橙=有 request 或 waiting / 红=有逾期，优先级 红 > 橙 > 蓝 > 灰（已定）。数字 = task + request + waiting，不含 notice。Live Activity 的 UI 和格式化已做，数据来源 M3 定，目前恒为空、隐藏 |
| 2.4 | 展开态列表（悬停展开） | ✅ | 排序直接用 `queueOrdered`；每行：来源图标、标题、相对时间、跳转按钮 |
| 2.5 | 点标题完成；⌥ 点推迟 30 分钟；notice 点一下转 task | ⬜ | **需要新 op**，见"M2 需要的协议扩展" |
| 2.6 | 全局快捷键弹快速录入 | ⬜ | 用 Carbon `RegisterEventHotKey`（不需要辅助功能权限）；解析用 `QuickEntry.parse`；默认键位未定 |
| 2.7 | `due_at` 到时：系统通知 + 刘海脉冲 | ⬜ | App 侧按最近的 due_at 设计时器（daemon 目前不发到期事件）；`UNUserNotificationCenter` 需要 .app bundle，ad-hoc 签名下要实测能否弹通知 |
| 2.8 | 验收：CLI 调用到刘海更新 ≤ 200 ms | ⬜ | 没有 Instruments：在 add 和 UI 刷新处打时间戳，或写一个 CLI → App 的计时脚本 |

### 构建路线（2.1，已定：SwiftPM）

没有 Xcode，用户选定 **SwiftPM + 打包脚本**，不走 XcodeGen（`project.yml` 已删）：

1. `Package.swift` 加可执行 target `PerchApp`（依赖 PerchCore、PerchClient），源码从 `PerchApp/` 移到 `Sources/PerchApp/`。
2. 可测的状态逻辑（事件合并、颜色点计算、排序、计时）放一个库 target（如 `PerchAppCore`），UI 层尽量薄，逻辑用 swift-testing 测。
3. `scripts/bundle-app.sh`：`swift build -c release --product PerchApp` → 组装 `Perch.app/Contents/{MacOS,Info.plist,Resources}`，`LSUIElement=true`，`codesign -s - --force`。
4. 更新 CLAUDE.md 的仓库结构与常用命令、删掉或标注 `project.yml`（装了 Xcode 再恢复也行）。
5. 窗口层可参考 NotchDo（MIT，保留版权头）；`CGSSpace.swift` 可单文件引用（MPL-2.0）。**不要复制 Boring Notch（GPL-3.0）。**

### App 连接 daemon 的做法

- 启动时 `PerchClient().watch()`，拿到确认后再 `send(list)` 拿快照；之后只按事件增量更新（`added` / `updated` 替换或插入，`removed` 删除），再重新 `queueOrdered`。
- `EventStream.next()` 是阻塞调用，放后台线程，结果切回主线程更新 `@Observable` / `ObservableObject`。
- perchd 没启动或重启：`next()` 返回 nil / 抛错 → 显示离线状态，退避重连（例如 0.5s → 5s），重连后重新拿快照。
- 队列顺序依赖"现在"（逾期、今日），需要一个分钟级计时器重排；这个计时器只负责重排，不能用来代替事件推送。

### M2 协议扩展：`update`（已实现）

- op `update` + `id` + `patch`（`title` / `kind` / `due_at` / `clear_due`，JSON snake_case），只改给了的字段；内容不变不发事件。
- `kind` 只能在 task ↔ notice 之间切；notice 转 task 时清掉 `expires_at`（否则会按 notice 的时间被 dismiss）；request 的 kind 不能改，也不能改成 request。
- CLI：`perch update <id> [--title …] [--kind task|notice] [--due …] [--no-due] [--json]`。推迟 30 分钟 = `--due +30m`（从现在起算，不是从原 due 起算）。

## 未决问题

| 问题 | 影响 | 状态 |
| --- | --- | --- |
| 装不装 Xcode（决定 M2 构建路线） | M2.1 | ✅ 已定：不装，SwiftPM + `scripts/bundle-app.sh` |
| Live Activity（"2 agents · 4m"）的数据从哪来：数据模型里没有"会话"。可选：SessionStart 时 `add --kind notice --key session-<id>` 加 meta 标记，Stop 时关闭；或新增 kind / 表 | M2.3、M3 | 未定；M2 先把 UI 做好、数据为空时隐藏 |
| `update` / snooze op 的形状 | M2.5 | ✅ 已定：通用 `update` op + `perch update`（见上方） |
| 全局快捷键默认值（快速录入；⌥⇧A / ⌥⇧D / ⌥⇧O） | M2.6、M4 | 未定（CLAUDE.md 也列了） |
| `link` 跳回终端的机制（Zed / Warp / tmux / iTerm） | M2.4 跳转按钮、M3 | M3 前定；M2 先用 `NSWorkspace.open` 处理 URL 和文件路径 |
| hook 等刘海的超时取 15 秒还是 30 秒 | M4 | 用一周后定 |
| 开源许可证 | 分发 | 未定 |

## 已知限制 / 技术债

- inbox 最后一行如果还没写完（没有换行符）就被读到，会被当成一整行吸收。`echo >>` 一次写入没问题。
- inbox 在"读取 → 核对 → 原地重写"之间有微秒级窗口，这期间追加的行可能丢失（已尽量缩小）。
- 从 `.build/` 执行 `perchd install` 会打印提醒：执行 `swift package clean` 后 agent 就会失效。日常使用要先把二进制复制到固定位置再装。
- 测试用的 Unix socket 放在 `/tmp/perch-test-*`：socket 路径上限 103 字节，`/var/folders/...` 太长。
- CLITests 通过 `--test-bundle-path` 找 `perch` 二进制（swift-testing 跑在 `swiftpm-testing-helper` 里，`Bundle.main` 不可用）。

## 工作约定（来自用户和 CLAUDE.md）

- 文档用中文；代码注释用英文，和现有代码保持一致。
- 每个清单项一个 commit，Conventional Commits（`feat(app): …` 等），提交前 `swift build && swift test` 必须通过；新行为先写测试。
- 做完一项：勾 `docs/MILESTONES.md` 对应的框，并更新本文进度表；未决问题定下来后同步更新 CLAUDE.md 的"未决问题"。
- 范围守卫：dispatch、stop / cancel、reply、MCP、双向同步、音乐 / HUD 等一律不做（见 CLAUDE.md）。
- 不主动 push；远端操作先问用户。

## M1 提交记录

```
29637c8 test: M1 acceptance — two terminals add and watch, key idempotency, latency
f8a9d60 feat(daemon): perchd install / uninstall as a launchd agent
19bba9a feat(daemon): render ~/.perch/todo.md and absorb ~/.perch/inbox.md
96624cd feat(cli): add --kind request --wait blocks until answered or expired
7203663 feat(cli): --due accepts @15:00 and +30m
c182769 feat(cli): wire add / ls / get / done / respond / rm / watch to perchd
dfbbf79 feat(daemon): push item.added / item.updated / item.removed to watch clients
990798f feat(daemon): add with an existing key updates the item instead of duplicating
a6da5be feat(daemon): implement ping / add / list / get / done / respond / remove
9fe8d0f feat(daemon): perchd starts, opens SQLite and listens on the Unix socket and 127.0.0.1:7331
a1b5930 test: migrate to swift-testing so `swift test` runs without Xcode
```
