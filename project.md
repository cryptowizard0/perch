# Perch — 开发路线与进度（交接文档）

> 给接手的 session：先读本文，再读 `CLAUDE.md`（架构铁律）、`docs/MILESTONES.md`（逐项验收清单）、`docs/PRD.md`（产品需求）。
> 本文负责"做到哪了、下一步怎么做、有哪些坑"；验收框以 `docs/MILESTONES.md` 为准，两边进度要同步更新。

最后更新：2026-09-28 · M1–M6 全部完成（M4–M6 由用户确认验收通过）· 同日方向调整为 agent 面板；M7 进行中：会话状态机（#15）、pid 存活检测（#16）已完成，下一步真实会话验收（#17）

## 总览

| # | 里程碑 | 状态 | 说明 |
| --- | --- | --- | --- |
| M1 | daemon + CLI + SQLite + watch | ✅ 完成 | 10 项全勾，73 个测试通过 |
| M2 | 刘海 UI | ✅ 完成 | 8 项全勾；CLI → 刘海 均值 11 ms。悬停、点击用户已确认 |
| M3 | Claude Code 被动接入（UserPromptSubmit / Notification / Stop） | ✅ 完成 | 152 个测试；用户在 Ghostty 和 Claude 桌面 App 里实测：变橙、notice、跳回原 tab 都正常 |
| M4 | PermissionRequest + 白名单 | ✅ 完成 | 用户确认验收通过（2026-09-28） |
| M5 | Codex 复用同一套 hook 脚本 | ✅ 完成 | 用户确认验收通过（2026-09-28） |
| M6 | Hermes 接入（改为 shell hook） | ✅ 完成 | 用户确认验收通过（2026-09-28） |
| M7 | 会话状态机（sessions 表、pid 存活检测、Claude Code / Codex hook 映射重写） | ⏳ 进行中 | #15 状态机 ✅；#16 存活检测 ✅；#17 真实会话验收待做。不动 UI |
| M8 | Agent 面板 UI；刘海 todo UI 下线 | 未开始 | |
| M9 | Hermes 迁到会话模型 | 未开始 | M8 验收后单独设计 |

## v0.2 方向调整（2026-09-28，用户逐项拍板）

产品从"agent 等待队列 + 待办"改为 **agent 的灵动岛面板**。完整设计写在 `docs/PRD.md` 的"v0.2 方向调整"和"Agent 面板"，这里只记决定和理由：

| 问题 | 决定 | 理由 / 备注 |
| --- | --- | --- |
| 一行对应什么 | 一个会话（`session_id`），首次 prompt 出现、SessionEnd 移除 | 和终端窗口一一对应；按轮会积历史，按目录会混状态 |
| 状态和颜色 | Needs you 🟠 / Failed 🔴 / Running 🟢 呼吸 / Done 🔵 静止 / Idle ⚪ | 等审批和等回答合并；出错单列（最容易被漏掉） |
| Done 何时变 Idle | 10 分钟后，或从刘海跳回那个终端后 | 否则整天一片蓝，信号失效 |
| 收起态 | 一个总色点 + 运行中数量；不再显示耗时 | 用户选最简方案（没选每会话一个点） |
| 展开态 | 按状态分组，组标题带数量 | |
| agent 图标 | 自己渲染的 12×12 单色像素图标；Claude Code = 像素小怪物 | 不打包商标文件；颜色只给状态圆点 |
| Running 第二行 | 本轮 prompt 首行 | 不装 PreToolUse；"当前动作"以后再说 |
| todo | UI 拿掉，底层和 CLI 不动；以后作为独立 tab 回来 | |
| 会话存哪 | SQLite（`sessions` 表） | 推翻 M3 "session 只在内存"的决定；重启后面板原样恢复 |
| 僵尸会话 | pid 存活检测为主（30 秒）+ 24 小时超时兜底 + 手动移除 | |
| 接哪些 agent | Claude Code + Codex；Hermes 暂不显示，M9 单独做 | Codex 几乎零成本，还能验证状态机与 agent 无关 |
| 会话与 item 分工 | 状态只在会话里；item 只剩 request | 一个概念只放一处 |
| 交互 | 点整行跳转；Allow / Deny；⌥⇧A / D / O；右键行移除；右键刘海只剩 Quit | |
| 提醒 | 只有刘海脉冲；不发系统通知、不加提示音 | |
| 文案 | 英文 | 和现有 UI、CLI 一致 |

过渡期注意：M7 之后 Hermes 的 waiting / notice 仍会写进 item 表，但 M8 起刘海不再显示 item（request 除外），所以 Hermes 的审批提示在 M9 前只能在终端 / Telegram 看到。

## 开发环境（重要）

- **本机没有 Xcode，只有 Command Line Tools**（Swift 6.1.2，`Package.swift` 仍是 tools-version 5.9 / Swift 5 语言模式）。
  - 没有 XCTest → 测试全部用 **swift-testing**（`import Testing`、`@Test`、`#expect`）。
  - `xcodebuild` 不可用 → App 用 SwiftPM 编译、`scripts/bundle-app.sh` 组装 `.app`（M2.1 定）。
  - SwiftUI / AppKit 可用：已验证 CLT 能编译运行 `NSPanel` + `NSHostingView`，并读到刘海安全区高度 33pt。Observation / Testing 宏插件也在。
  - `screencapture -x` 可用（有屏幕录制权限）：改 UI 后截图 + `sips -c` 裁剪看效果。**不能合成鼠标 / 键盘事件**（`CGPreflightPostEventAccess` 为 false，System Events 无辅助功能权限）→ 悬停、点击、快捷键只能靠人工或 `PERCH_PIN_EXPANDED=1` 截图。
  - 看窗口位置不需要权限：`CGWindowListCopyWindowInfo` 过滤 owner "Perch"。
- git 提交用 1Password SSH 签名；1Password 锁着时报 "failed to fill whole buffer"，让用户解锁后重试（不要自己关签名）。
  - `codesign` 可用（ad-hoc 签名 `codesign -s -`）。`actool`（Asset Catalog）不可用 → 图标用 png / icns。
- `/usr/local/include/sqlite3.h` 是一个手动装的野头文件，会让 `import SQLite3` 编译失败。所以 daemon 用 `Sources/CSQLite` 自己声明 sqlite3 函数；新增函数就加到 `Sources/CSQLite/include/CSQLite.h`。**不要删那个系统文件，也不要改回 `import SQLite3`。**
- GitHub 走 ssh 偶尔失败（ssh-agent 签名问题）；依赖已在 `.build` 缓存。不要随意加新依赖。

## 常用命令

```
swift build && swift test                     # 每次提交前必须通过
PERCH_HOME=/tmp/perch-dev swift run perchd    # 隔离数据跑 daemon，不碰 ~/.perch
PERCH_HOME=/tmp/perch-dev swift run perch ls
scripts/bundle-app.sh && open .build/Perch.app  # 刘海 App（CONFIG=debug 出调试版）
PERCH_HOME=/tmp/perch-dev PERCH_PIN_EXPANDED=1 .build/Perch.app/Contents/MacOS/Perch   # 隔离数据 + 常开展开态，方便截图
scripts/measure-latency.sh                     # CLI → 刘海延迟
swift run perchd install --dry-run            # 看 launchd plist；install / uninstall 真装真卸
```

## 当前代码地图（M2 结束时）

```
Sources/PerchCore/     纯逻辑，无 I/O，App 可直接复用：
  Models.swift           Item / Event；宽松解码（只有 title 必填）；queueRank / queueOrdered（刘海排序就用它）
  Protocol.swift         Request / Response / Filter（含 all）；PerchJSON（ISO-8601、sortedKeys、不转义 /）
  DueParser.swift        @15:00 / +30m / +1h30m / ISO-8601
  Markdown.swift         MirrorRenderer（todo.md）、Inbox（inbox.md 解析）、QuickEntry（"标题 @15:00" → 标题 + due）
  Paths.swift            ~/.perch（PERCH_HOME 可覆盖）
  Sessions.swift         Session / SessionStatus / SessionReport / SessionEvent（会话，M7 起入库）
  AgentProcess.swift     ProcessEntry / AgentProcess.find：沿父进程链找 agent 进程（纯函数）
  Hooks.swift            HookInput / HookAdapter（hook 事件 → 请求；PermissionRequest 的 ask / terminal 计划；决定 JSON）
  Allowlist.swift        刘海可批准的范围（tools / bash / protected_paths）
  PermissionPrompt.swift request 显示的完整文本；JSONValue.swift 任意 JSON（tool_input）
  TerminalLink.swift     perch-terminal://<app>?id=&cwd=&bundle=
Sources/PerchClient/   PerchClient.send / watch() → EventStream；BufferedSocket（阻塞式 socket + 读缓冲）；
                       SystemProcesses（sysctl 读进程：hook 的祖先链、perchd 的存活探测）
Sources/PerchDaemon/   Daemon（串行队列 + 订阅者 + 过期计时器 + 镜像 + inbox 监听）、Service（各 op）、Store（sqlite：items + sessions）、SessionRegistry（会话状态机）、
                       Server / HTTPConnection（Unix socket + 127.0.0.1 HTTP）、Files（MirrorWriter / InboxWatcher）、LaunchAgent
Sources/perch/         CLI：add / ls / get / done / update / respond / rm / watch / session / hook / hooks
  Hook.swift             `perch hook <agent>`：stdin → HookAdapter → perchd；Ghostty 探测；HookLog
  HooksInstall.swift     `perch hooks install|uninstall claude-code|codex|hermes`（HookFile 协议：HookSettings 改 JSON，HermesHooks 管 config.yaml 里的标记块）
  AllowlistCommand.swift `perch allowlist show|check|init`；RequestWaiter（Perch.swift）供 add --wait 和 hook 共用
Sources/perchd/        入口：run（默认）/ install / uninstall
Sources/PerchAppCore/  刘海 App 的可测逻辑（无 AppKit）：
  NotchGeometry          刘海矩形、收起 / 展开 frame、无刘海胶囊
  QueueState             快照 + 事件合并、Summary（数字）、Signal（颜色，红 > 橙 > 蓝 > 灰）、是否脉冲
  QueueConnection        后台线程：watch → list → 事件；离线退避重连 0.5→5 s
  QueueModel             @MainActor ObservableObject：状态、分钟 / 到期 tick、click / quickAdd、flash、onDue / onApply
  Click / RowFormat      点击 → 请求映射；行内时间文本、来源图标、link → URL
  Jump                   JumpTarget（终端 / URL）、GhosttyScript（focus 的 AppleScript）
  DueReminders / HotKey / LiveActivity / RelativeTime
Sources/PerchApp/      AppKit + SwiftUI 壳：NotchPanel / NotchWindowController（悬停、布局、换屏）、NotchView / ExpandedList、
                       QuickEntry（面板）、GlobalHotKey（Carbon）、Notifier（UNUserNotification）、Jumper（跳终端）、AppDelegate
packaging/Info.plist · scripts/bundle-app.sh · scripts/measure-latency.sh · scripts/install.sh
Tests/PerchCoreTests/    纯逻辑
Tests/PerchAppCoreTests/ App 纯逻辑
Tests/PerchDaemonTests/  进程内起 daemon（Support.swift 的 TestDaemon）+ 跑真实 perch 二进制（CLITests / AcceptanceTests）；
                         App 连接和 QueueModel 也在这里测（AppConnectionTests / AppModelTests / NotchLatencyTests）
```

## 已定下的契约（M2+ 依赖，改之前先想清楚）

- Wire：Unix socket 上一行一个 JSON；HTTP `POST /rpc` 同一套 JSON。`watch` 先回 `{"ok":true}` 确认，再逐行推 `{"ok":true,"event":{…}}`。**确认之后发生的变化保证能收到**，所以客户端正确做法是：先 `watch()`，再 `list` 拿快照。
- op：`ping / add / list / get / done / respond / remove / update / watch / session_start / session_end / sessions / session_report / session_seen / session_remove`。
- session（M7 起）：进 SQLite `sessions` 表，五种状态，由 `session_report` 驱动（见下方"M7 进度"）；`watch` 另推 `session.updated`（每次变化）和 `session.ended`（移除）。以下是 M3 的旧约定，已作废的部分见 M7：session 只在 perchd 内存里，不进 SQLite；`watch` 推 `{"ok":true,"session_event":{…}}`，`EventStream.next()` 只返回 item 事件（老客户端不受影响），`nextPush()` 两种都给。每条消息带观测时间，比该 id 最后一条旧的消息丢弃（async hook 会乱序）；超过 3 小时没结束的 turn 自动清掉。`list` 默认只返回 open + waiting，已按队列顺序排好。
- `add --key`：同 key 更新原项（保留 id 和 created_at），会重新打开已关闭项并清空旧 response；内容完全相同的重复 add 不发事件。
- request：默认 status waiting、options `allow,deny`；`respond` 校验选项，回应后 status 变 done。
- `expires_at`：到点 daemon 把 open / waiting 项置为 dismissed 并推 `item.updated`（notice 自动消失、request 超时都靠它）。
- `perch add --kind request --wait`：有回应 exit 0 并打印回应；过期 / 被 done / 被 rm 都 exit 3。**exit 3 永远不等于放行。**
- CLI 错误：stderr 一行 `perch: …`；`--json` 时 stdout 为 `{"ok":false,"error":"…"}`；exit 非 0（参数错误 64）。
- HTTP 拒绝带 `Origin` 头、非 `application/json`、Host 不在白名单（127.0.0.1 / localhost / [::1] / host.docker.internal）的请求。
- 文件：`todo.md` 只读（0444），内容变了才重写；`inbox.md` 启动时创建，只吸收 `- [ ]` / `* [ ]` 行，其余内容保留。

## M2 进度（刘海 UI，已完成）

| # | 任务 | 状态 | 要点 |
| --- | --- | --- | --- |
| 2.1 | App 可编译运行、无 Dock 图标 | ✅ | `scripts/bundle-app.sh` → `.build/Perch.app`；`lsappinfo` 显示 type="UIElement" |
| 2.2 | NSPanel 贴刘海；无刘海退化为顶部居中胶囊 | ✅ | `NSScreen.safeAreaInsets.top > 0` 判断有无刘海；`auxiliaryTopLeftArea/RightArea` 算刘海宽度；多屏、换屏要跟着走 |
| 2.3 | 收起态：数字、颜色点、Live Activity | ✅ | 颜色：灰=空 / 蓝=有待办 / 橙=有 request 或 waiting / 红=有逾期，优先级 红 > 橙 > 蓝 > 灰（已定）。数字 = task + request + waiting，不含 notice。Live Activity 的 UI 和格式化已做，数据来源 M3 定，目前恒为空、隐藏 |
| 2.4 | 展开态列表（悬停展开） | ✅ | 排序直接用 `queueOrdered`；每行：来源图标、标题、相对时间、跳转按钮。悬停 120 ms 展开、离开 300 ms 收起；request 标题完整显示不截断 |
| 2.5 | 点标题完成；⌥ 点推迟 30 分钟；notice 点一下转 task | ✅ | 用新 `update` op。request 的标题点了没反应（M4 用 Allow / Deny / 终端按钮），避免误点关掉请求 |
| 2.6 | 全局快捷键弹快速录入 | ✅ | ⌥⇧Space（已定），`defaults write dev.perch.app QuickEntryHotKey …` 可改；非激活但可成为 key 的 NSPanel，不抢前台 App 焦点；右键刘海也能打开 |
| 2.7 | `due_at` 到时：系统通知 + 刘海脉冲 | ✅ | App 侧按最近的 due_at 设计时器（daemon 不发到期事件）；同一 (id, due) 只提醒一次，App 启动前就逾期的不提醒，推迟后换了 due 会再提醒。ad-hoc 签名的 .app 能弹出系统授权框；`swift run` 裸二进制没有 bundle，只脉冲不发通知 |
| 2.8 | 验收：CLI 调用到刘海更新 ≤ 200 ms | ✅ | `NotchLatencyTests`（到 QueueModel）+ `scripts/measure-latency.sh`（真 App，含 UI 布局那一轮）：release 均值 11 ms、最差 14 ms |

### 构建路线（2.1，已定：SwiftPM）

没有 Xcode，用户选定 **SwiftPM + 打包脚本**，不走 XcodeGen（`project.yml` 已删）：

1. `Package.swift` 加可执行 target `PerchApp`（依赖 PerchCore、PerchClient），源码从 `PerchApp/` 移到 `Sources/PerchApp/`。
2. 可测的状态逻辑（事件合并、颜色点计算、排序、计时）放一个库 target（如 `PerchAppCore`），UI 层尽量薄，逻辑用 swift-testing 测。
3. `scripts/bundle-app.sh`：`swift build -c release --product PerchApp` → 组装 `Perch.app/Contents/{MacOS,Info.plist,Resources}`，`LSUIElement=true`，`codesign -s - --force`。
4. 更新 CLAUDE.md 的仓库结构与常用命令、删掉或标注 `project.yml`（装了 Xcode 再恢复也行）。
5. 窗口层可参考 NotchDo（MIT，保留版权头）；`CGSSpace.swift` 可单文件引用（MPL-2.0）。**不要复制 Boring Notch（GPL-3.0）。**

### App 连接 daemon 的做法（已按此实现：`QueueConnection` / `QueueModel`）

- 先 `watch()`，拿到确认后再 `list` 拿快照；之后只按事件增量更新（`added` / `updated` 替换或插入，closed / `removed` 删除），显示时 `queueOrdered`。
- `EventStream.next()` 阻塞，跑在专用线程；结果切回主线程更新 `QueueModel`（ObservableObject）。停止用 `EventStream.interrupt()`（socket shutdown）唤醒阻塞的读。
- perchd 没启动或重启 → 离线图标，退避重连 0.5 s → 5 s，重连后重新拿快照。
- "现在"在分钟边界和下一个 due 时刻各 tick 一次，只负责重排 / 变红 / 到期提醒，不代替事件推送。

### M2 人工验收（我没法合成鼠标键盘事件，这几项需要人手点一遍；悬停、点击已由用户确认）

```
swift build && scripts/bundle-app.sh && open .build/Perch.app     # perchd 要在跑（perchd install 或前台 perchd）
```
- [x] 鼠标移到刘海：约 0.1 s 展开；移开约 0.3 s 收起；贴着菜单栏划过不误触
- [x] 点任务标题 → 完成消失；⌥ 点 → 右侧时间变 "in 30m"；点 notice → 变成白色 task 且不再自动消失；点 request 标题无反应
- [ ] ⌥⇧Space 弹出快速录入，输入"回复 X 的邮件 +1m"回车；不抢当前 App 焦点；Esc / 点别处关闭
- [ ] 首次启动允许通知；1 分钟后弹系统通知、刘海脉冲、点变红
- [ ] 右键刘海：New Task… / Quit Perch
- [ ] 接外接显示器 / 合盖：刘海或胶囊跟着换位置

## M3 进度（Claude Code 被动接入）

用户定的：Live Activity = 内存 session、按轮计时（UserPromptSubmit → Stop）；终端 = Ghostty；不接 `idle_prompt`。

| # | 任务 | 状态 | 要点 |
| --- | --- | --- | --- |
| 3.1 | session（Live Activity 数据） | ✅ | `session_start/session_end/sessions` op、`perch session start|end|ls`、`session.*` 事件；只在内存；乱序消息按时间戳丢弃（平局算 start 新）；3 小时没结束自动清 |
| 3.2 | `perch done --key` | ✅ | hook 只知道 key 不知道 id |
| 3.3 | `perch hook claude-code` | ✅ | 映射见 CLAUDE.md "Hook 适配"；不打 stdout、exit 0、错误写 `~/.perch/hook.log` |
| 3.4 | `perch hooks install/uninstall claude-code` | ✅ | 合并写 settings.json，备份 `.perch-backup`，只删自己的；对真实 settings 的 dry-run 只多出 5 条 Perch hook |
| 3.5 | App：Live Activity + 跳回 Ghostty | ✅ | `perch-terminal://ghostty?id=&cwd=&bundle=`；osascript focus；失败退化为激活 App |
| 3.6 | 验收：真实会话 | ✅ | 已用 install.sh 装到本机；Ghostty 的 terminal id 探测没弹授权；桌面 App 会话也会计入 Live Activity（跳转只激活 App），用户认可 |

### M3 验收步骤

```
scripts/install.sh          # perch/perchd → ~/.local/bin，Perch.app → ~/Applications，launchd，hooks
```
然后在 Ghostty 里开 `claude`：
- [x] 发一条 prompt → 刘海左侧出现 "1 agent · <1m"
- [x] 让它跑一个需要权限的命令 → 刘海变橙，列表里 "项目名 · Claude needs your permission…"
- [x] 在终端里批准 → 跑完后橙色消失，出现灰色 notice（最后一句话摘要），10 分钟后自动消失；Live Activity 消失
- [x] 点那条的终端按钮 → 回到那个 Ghostty tab（第一次会弹"Perch 想控制 Ghostty"，允许）
- [x] `~/.perch/hook.log` 没有异常
- hook 里的 osascript 问 Ghostty 聚焦的 terminal：实测不弹授权。

## M4 进度（PermissionRequest + 白名单）

用户定的：等刘海 20 秒（`perch hooks install claude-code --wait N` 可改）；总是先走刘海（不判断人是否在终端前）；⌥⇧A / ⌥⇧D 只在有 request 时注册，⌥⇧O 在队列非空时注册。

| # | 任务 | 状态 | 要点 |
| --- | --- | --- | --- |
| 4.1 | 白名单 | ✅ | `Allowlist`（PerchCore）+ `~/.perch/allowlist.json` + `perch allowlist show/check/init`；缺文件用默认值，坏文件什么都不放（fail closed） |
| 4.2 | PermissionRequest 适配 | ✅ | 白名单内：request + 等 `--wait` 秒，回应就打印 `hookSpecificOutput.decision.behavior`；超时 / 白名单外：不打印，发"去终端" waiting（key 同 Notification，迟到的 permission_prompt 不会覆盖命令原文）。新增 PostToolUse / PostToolUseFailure：工具跑了就 resolve waiting，不再等到 Stop |
| 4.3 | 刘海 request 行 + 快捷键 | ✅ | 完整命令（等宽、可选中）、用途 · 项目、Allow / Deny / Terminal；"去终端"行写明原因，点标题跳终端；GlobalHotKey 按 id 分发（修了多个热键互相触发的问题） |
| 4.4 | 验收 | ✅ | 用户确认通过（2026-09-28） |

### M4 验收步骤

```
scripts/install.sh      # 升级二进制和 App，并把新的 hook（PermissionRequest / PostToolUse*）写进 settings.json
```
- [x] Ghostty 里让 claude 跑 `npm test`（或 `git status`）：终端显示 "Waiting for Perch…" 转圈，刘海出现 request；点 Allow（或 ⌥⇧A）→ 终端不弹提示，命令直接跑
- [x] 让它跑 `rm -rf <某个临时目录>`：终端立刻弹原生提示；刘海只有一条"Answer in the terminal · …"，点它回到那个 tab；在终端批准后橙色马上消失
- [x] 再来一次 `npm test`，不理刘海：20 秒后终端原生提示正常弹出，刘海那条变成"去终端"
- [x] Deny（⌥⇧D）：Claude 收到 "Denied by the user from the Perch notch." 并继续
- 风险：hook 运行期间终端是否真的只转圈、不同时弹提示框（文档没写死），以实测为准。

## M5 进度（Codex）

按官方文档（https://learn.chatgpt.com/docs/hooks ）和本机 codex 0.155.1 二进制里的事件名核对过：

- stdin JSON 与 Claude Code 同形（多 `turn_id` / `model`，`transcript_path`、`description`、`last_assistant_message` 可能是 null，解码都忽略）。
- PermissionRequest 返回格式与 Claude Code **完全相同**（`hookSpecificOutput.decision.behavior`），`HookAdapter.decision` 不分支。不能返回 `updatedInput` / `updatedPermissions` / `interrupt`。
- 事件：有 UserPromptSubmit / PermissionRequest / PostToolUse / Stop / SessionEnd，**没有 Notification / StopFailure / PostToolUseFailure**，多 `Interrupt`（Esc 打断，不发 Stop）→ 适配器把 Interrupt 当成 session_end + resolve waiting。
- 所以 Codex 的橙色只来自 PermissionRequest：白名单内是 request，白名单外 / 超时是"去终端" waiting；Codex 自己提问（没有 hook）不会变橙。
- Codex 的工具名：`Bash`（`tool_input.command` 是字符串）、`apply_patch`（`command` 是整段 patch）、MCP 工具。后两者不在白名单 → 一律去终端，刘海显示完整 patch。
- SessionEnd 在 Codex 里总是同步跑，默认 1 秒、最多 3 秒 → 装成同步、timeout 3。Interrupt 同样限 1–3 秒（后台跑也一样）→ async、timeout 3。
- Stop / Interrupt 的 stdout 只能是空或 JSON（纯文本无效）；适配器本来就不打印，验收时留意 Codex 对空输出的处理。
- 信任：Codex 按 hook 的 hash 记信任，新装或改了（包括换 `--binary` / `--wait`）都要在 codex 里 `/hooks` 重新确认，否则静默跳过。
- 本机 `~/.codex/hooks.json` 已有 Superset 的 SessionStart / UserPromptSubmit / Stop hook，安装只追加，dry-run 核对过不动它们。

| # | 任务 | 状态 | 要点 |
| --- | --- | --- | --- |
| 5.1 | `perch hook codex` | ✅ | 同一个适配器；新增 Interrupt；Codex stdin 的单测 + 真 perchd 的端到端测试（`CodexHookTests`） |
| 5.2 | `perch hooks install|uninstall codex` | ✅ | `~/.codex/hooks.json`（`$CODEX_HOME`）；install.sh 在有 `~/.codex` 时一起装；装完提示去 `/hooks` 信任 |
| 5.3 | 验收 | ✅ | 用户确认通过（2026-09-28） |

### M5 验收步骤

```
scripts/install.sh      # 升级二进制，并把 Codex hook 写进 ~/.codex/hooks.json
```
然后在 Ghostty 里开 `codex`，先 `/hooks` 把 6 个 Perch hook 标为信任：
- [x] 发一条 prompt → 刘海左侧出现 "1 agent · <1m"（来源图标是 `</>`）
- [x] 让它跑 `cargo test`（或 `git status`，需要审批的沙箱模式下）：刘海出现 request，Allow → Codex 不弹审批直接跑；Deny → Codex 收到拒绝
- [x] 让它改文件（apply_patch）或跑 `rm -rf <临时目录>`：Codex 立刻弹原生审批，刘海只有一条"去终端"，批准后橙色消失
- [x] 一轮跑完 → 灰色 notice，Live Activity 消失；跑到一半按 Esc → Live Activity 也消失（Interrupt）
- [x] `~/.perch/hook.log` 没有异常
- 已用 `codex exec --dangerously-bypass-hook-trust` 实测（2026-09-28）：UserPromptSubmit → session.started，Stop → session.ended + notice（"perch-m5 · ok"），Codex 没报任何 hook 错误（Stop 的空 stdout 没问题），`hook.log` 为空；hook 子进程继承了 `__CFBundleIdentifier`（从 Claude 桌面 App 启动时是 `com.anthropic.claudefordesktop`）。
- `codex exec` 是非交互的，不会发审批（"does not allow requests for escalated permissions"），所以 PermissionRequest、Interrupt 只能在交互式 codex 里验收。
- 测试时不要 `pkill -f "perch watch"`：会把别的会话的 watch 一起杀掉，只按 PID 杀自己起的进程。
- 风险：Codex 的 hook 子进程是否继承 `TERM_PROGRAM` / `__CFBundleIdentifier`（决定跳转按钮），以实测为准；`async` hook 在 Codex 里是否真的不阻塞，也以实测为准。

## M6 进度（Hermes，改为 shell hook）

用户定（2026-09-28）：原计划"Docker 里的 Hermes 走 `curl host.docker.internal:7331/rpc`"不成立——本机的 Hermes Agent（Nous Research，v0.18）跑在宿主机上（`terminal.backend: local`，`hermes gateway run` 常驻），Docker 也没开。Hermes 有和 Claude Code 类似的 shell hook，于是做成 hook 适配器。

按 Hermes 源码（`~/.hermes/hermes-agent`：`agent/shell_hooks.py`、`tools/approval.py`、`agent/turn_*.py`）核对：
- stdin：`{"hook_event_name","tool_name","tool_input","session_id","cwd","extra":{…}}`；审批事件的 `session_id` 是空串，身份在 `extra.session_key`。`extra` 里还有整段 `conversation_history`，解码时跳过。
- shell hook 用 `subprocess.run` **同步**执行，默认 60 秒、上限 300 → 装成 timeout 10；stdout 的 JSON 会被解析（`pre_llm_call` 的 `context` 进 LLM 上下文），适配器照旧不打印。
- `on_session_end` 在**每轮**结束都触发（`run_conversation` 末尾，含中断），不是会话结束 → 当 session_end 用；`post_llm_call` 只在有回复、没被中断时触发 → 发 notice。
- `pre_approval_request` / `post_approval_response` 只能观察（返回值被忽略），CLI 和 gateway（Telegram 等）都会触发；`choice` 是 once / session / always / deny / timeout。刘海只能提示去哪儿回答。
- 同意：每个 (事件, 命令) 首次要确认，存 `~/.hermes/shell-hooks-allowlist.json`；非 TTY（gateway）没确认过的 hook 会被静默跳过 → 先在终端跑一次 `hermes` 确认，再 `hermes gateway restart`。
- `hermes hooks list` / `hermes hooks doctor` 可以检查。
- 已用 Hermes 自己的解析器（`iter_configured_hooks`）核对 dry-run 结果：5 个 hook 都认，config 其余部分不变。

| # | 任务 | 状态 | 要点 |
| --- | --- | --- | --- |
| 6.1 | 适配器 | ✅ | `HookAdapter` 加 Hermes 分支；`HermesAdapterTests` + 真 perchd 的 `HermesHookTests` |
| 6.2 | `perch hooks install|uninstall hermes` | ✅ | config.yaml 末尾的标记块；已有非空 `hooks:` 拒绝，`hooks: {}` 之类会替换；install.sh 在有 `~/.hermes` 时一起装（失败不影响其余安装） |
| 6.3 | 刘海文案 | ✅ | `RowFormat.answerHint`：终端 / "Answer in Telegram" |
| 6.4 | 验收 | ✅ | 用户确认通过（2026-09-28） |

### M6 验收步骤

```
scripts/install.sh              # 或只装 hook：perch hooks install hermes
hermes                          # 终端里跑一次，确认 Perch 的 5 个 hook（或 hermes --accept-hooks）
hermes gateway restart          # gateway 才会加载新 hook
hermes hooks list               # 5 个都应是 allowed
```
- 2026-09-28 已装到本机（`scripts/install.sh`），5 个 hook 已记入 Hermes 的 allowlist，gateway 重启后加载无警告；`hermes -z` 一轮实测：出现 notice "tmp · ok"，session 正常结束，`hook.log` 为空。
- [x] 终端里 `hermes` 发一条消息 → 刘海出现 "1 agent · …"（纸飞机图标）；回复后 Live Activity 消失，出现灰色 notice
- [x] 让它跑 `rm -rf <临时目录>`：刘海变橙，显示完整命令和原因（"Answer in the terminal · …"）；在 Hermes 里回应后橙色消失
- [x] 从 Telegram（gateway）让它跑一条危险命令：刘海显示 "Answer in Telegram"；在 Telegram 里回应后消失
- [x] `~/.perch/hook.log` 没有异常；Hermes 每轮没有明显变慢（hook 同步执行）
- 代码审查后修的（2026-09-28）：审批 key 加 `tool_call_id`（同一聊天排队的多个审批、共用 `default` 的多个 CLI 会话不再互相清掉）；审批 15 分钟过期兜底（Hermes 崩了不会永远橙）；忽略 `platform: subagent` 和后台复盘（`agent/background_review.py`，共用 session_id，靠 prompt 结尾 "You can only call memory and skill management tools" 识别）；Hermes 重写 config.yaml 丢标记后仍能认出 / 卸载 Perch 的 hook；CLI 审批跳到同目录那一轮的终端；gateway 事件一律不带终端链接。
- 实测延迟（release，隔离 perchd）：`perch hook hermes` 处理带 5 MB conversation_history 的 `pre_llm_call` 中位 12 ms。
- 仍有的限制：gateway 的每条消息都会留一条 notice（10 分钟消失），嫌吵再说；后台复盘的 `on_session_end` 没法识别，若和你的下一轮重叠，会提前结束那一轮的 Live Activity；gateway 审批没有终端可跳，点标题会直接标完成（手动清掉的出口）。

## M7 进度（会话状态机）

| # | 任务 | 状态 | 要点 |
| --- | --- | --- | --- |
| 7.1 | 会话状态机（#15） | ✅ | 见下 |
| 7.2 | pid 存活检测 + 24 小时兜底（#16） | ✅ | 见下 |
| 7.3 | 真实会话验收（#17） | 未开始 | |

7.1 的做法（2026-09-28）：
- 适配器把每个 hook 事件归一成 `SessionReport`（prompt / waiting / resume / stop / failure / interrupt / end），op `session_report`；状态机在 perchd 的 `SessionRegistry`，和 agent 无关。表见 `SessionReport` / `HookAdapter` 的文档注释。
- `sessions` 表，schema v2（`PRAGMA user_version` 从 1 迁到 2，items 不动）。`started_at` = 首次出现，`turn_started_at` = 本轮开始，`status_at` = 进入当前状态（Done → Idle 不改它，Idle 行仍能显示"多久前完成"），`updated_at` = 最后一次事件的观测时间。
- 乱序：报告的 `at`（整秒，未来时间按 perchd 时钟截断）比 `updated_at` 旧就丢弃，平局照收（和 M3 一样）。被移除（end / rm）的会话在内存里记 10 分钟移除时间，更早的事件不会让它复活；更新的事件会。
- 不再有 M3 的"3 小时没结束的 turn 自动清掉"：Claude Code 按 Esc 不发 Stop，会话会一直 Running，等 #16 的进程检测。
- request：resume / stop / failure / interrupt / end 会关掉 `meta.session_id` 指向该会话的 request（done、不带回应）。PermissionRequest hook 的 request 没回应就结束（过期、被 done / rm、被这样关掉）一律补发"去终端"：同一轮并行的另一个工具跑完（PostToolUse）也会关掉它，这时终端提示确实在等人。刘海 Allow / Deny 后 hook 发一条 resume，会话回到 Running（Deny 后不会有 PostToolUse）。
- 会话的 detail：白名单内是完整命令（Allow / Deny 在 request 上）；白名单外是"完整命令\nAnswer in the terminal: 原因"；超时是"完整命令\nAnswer in the terminal"；提问是 Notification 的 message（没有就 "Waiting for your answer"）。
- 事件：每次变化推 `session.updated`，移除推 `session.ended`，新一轮开始额外先推 `session.started`（给老客户端）。刘海的 Live Activity 只数 Running，按 `turn_started_at` 计时。
- daemon 的计时器按注入的时钟算延迟（`next - now()`），测试挪时钟后随便发个请求就能触发 Done → Idle。
- 过渡期：Claude Code / Codex 仍并行发 waiting / notice item（#19 下线）；Hermes 不变（`session_start` = running，`session_end` = 移除）。
- 已知限制：时间是整秒，同一秒内乱序到达的两个事件仍按到达顺序生效（和 M3 一样）；移除记忆只在内存里，perchd 重启后迟到的旧事件可能让已移除的会话复活（进程检测会再清掉它）；并行工具时一个工具的 PostToolUse 会把会话从 waiting 拉回 running，直到那个 PermissionRequest 超时交给终端。

7.2 的做法（2026-09-28）：
- `perch hook` 从自己往上走父进程链，找 argv[0] 最后一段叫 `claude`（claude-code）/ `codex`（codex）的最近祖先（`PerchCore/AgentProcess.swift`，纯函数，给进程表就能测）；每条 `session_report` 带它的 pid 和启动时间（整秒）。Hermes 不找（M9）。
- 进程表：`PerchClient/SystemProcesses.swift`，sysctl（`KERN_PROC_PID` 拿 ppid / 启动时间，`KERN_PROCARGS2` 拿 argv[0]），只读 hook 自己的祖先链，不起子进程。僵尸进程算没了。
- **坑**：内核的进程名（`p_comm`，`ps -c` 不显示它）是可执行文件的真实文件名。终端里的 `claude` 是 `~/.local/bin/claude` → `~/.local/share/claude/versions/2.1.x` 的符号链接，内核名是 `2.1.x`；所以按 argv[0] 认。
- perchd：`Daemon(probe:livenessInterval:)`，probe 是 `(pid) -> 启动时间?`（默认 `SystemProcesses.startTime(of:)`，测试注入假的）。每 30 秒 `SessionRegistry.reap()`：有 pid 的，进程没了或启动时间不同（pid 复用）就移除；没 pid 的，24 小时没有事件就移除。移除和 `perch session rm` 一样：推 `session.ended`、记移除时间（之前观测到的迟到事件不会让它复活）、关掉它的 request。进程活着的会话再安静也不动。perchd 启动时先扫一遍（停机期间退出的 agent 立刻清掉）。来自已死进程的报告（`end` 除外）直接丢弃：agent 死了但 PermissionRequest hook 还在等，之后发的"去终端"不会让会话复活。新 pid 连同它的启动时间一起替换，不会把旧启动时间配给新 pid。
- 实测（2026-09-28，本机）：Claude 桌面 App 每个会话一个进程（`Claude` → `disclaimer` → `…/claude-code/2.1.x/claude.app/Contents/MacOS/claude`），hook 能找到 → 桌面会话按 pid 清理，不走 24 小时。Codex 桌面 App（ChatGPT.app）所有会话共用一个 `codex app-server` 进程，只有退出 App 才会被清。隔离 perchd 上用"以 `claude` 为名启动的 bash"跑 hook、再 `kill -HUP` 模拟关 tab：20 秒后推 `session.ended`。真 Ghostty tab 的验收并入 #17。
- 已知限制：同一个 session id 同时开在两个进程里（另一个 tab `--resume`），以最后上报的 pid 为准，关掉那个 tab 就移除；那个"去终端" waiting item（过渡期的旧 item，#19 下线）不会随会话被清。用 npm 装的 Claude Code（`node …/cli.js`）argv[0] 可能是 `node`（未实测），那样找不到 pid → 走 24 小时兜底。

### M2 协议扩展：`update`（已实现）

- op `update` + `id` + `patch`（`title` / `kind` / `due_at` / `clear_due`，JSON snake_case），只改给了的字段；内容不变不发事件。
- `kind` 只能在 task ↔ notice 之间切；notice 转 task 时清掉 `expires_at`（否则会按 notice 的时间被 dismiss）；request 的 kind 不能改，也不能改成 request。
- CLI：`perch update <id> [--title …] [--kind task|notice] [--due …] [--no-due] [--json]`。推迟 30 分钟 = `--due +30m`（从现在起算，不是从原 due 起算）。

## 未决问题

| 问题 | 影响 | 状态 |
| --- | --- | --- |
| 装不装 Xcode（决定 M2 构建路线） | M2.1 | ✅ 已定：不装，SwiftPM + `scripts/bundle-app.sh` |
| Live Activity（"2 agents · 4m"）的数据从哪来 | M2.3、M3 | ✅ 内存 session，按轮计时（UserPromptSubmit → Stop / StopFailure / SessionEnd） |
| `update` / snooze op 的形状 | M2.5 | ✅ 已定：通用 `update` op + `perch update`（见上方） |
| 全局快捷键默认值（快速录入；⌥⇧A / ⌥⇧D / ⌥⇧O） | M2.6、M4 | ✅ 快速录入 ⌥⇧Space；其余沿用 PRD，M4 实现 |
| `link` 跳回终端的机制（Zed / Warp / tmux / iTerm） | M2.4 跳转按钮、M3 | ✅ Ghostty AppleScript focus terminal id；其他终端激活 App |
| hook 等刘海的超时取 15 秒还是 30 秒 | M4 | ✅ 先用 20 秒（`--wait` 可改），用一周后再看 |
| 开源许可证 | 分发 | 未定 |

## 已知限制 / 技术债

剩余工作都已开成 GitHub issue：https://github.com/cryptowizard0/perch/issues
（#1 M4 验收 · #2 M5 Codex · #3 M6 Hermes · #4 许可证 · #5 README · #6 #7 inbox · #8 Esc 打断 · #9 自启 + 图标 · #10 URL scheme / 其他终端 · #11 展开态高度 · #12 UI 自动化测试 · #13 等待时长复盘）。做完一项就关对应 issue。

- inbox 最后一行如果还没写完（没有换行符）就被读到，会被当成一整行吸收。`echo >>` 一次写入没问题。
- inbox 在"读取 → 核对 → 原地重写"之间有微秒级窗口，这期间追加的行可能丢失（已尽量缩小）。
- 从 `.build/` 执行 `perchd install` 会打印提醒：执行 `swift package clean` 后 agent 就会失效。日常使用要先把二进制复制到固定位置再装。
- 测试用的 Unix socket 放在 `/tmp/perch-test-*`：socket 路径上限 103 字节，`/var/folders/...` 太长。
- CLITests 通过 `--test-bundle-path` 找 `perch` 二进制（swift-testing 跑在 `swiftpm-testing-helper` 里，`Bundle.main` 不可用）。
- Perch.app 还不会开机自启（perchd 有 launchd，App 没有）；也没有图标（`actool` 不可用，要做就放 .icns 到 `packaging/`）。
- 展开态高度是估算的（request 按 52 字 / 行算），很长的 request 靠列表滚动兜底。
- `link` 只能打开 URL 和绝对 / `~` 路径；tmux 等终端会话引用没有跳转按钮，等 M3 定机制。
- Esc 打断一轮时 Claude Code 不发 Stop（Codex 有 Interrupt，没这个问题）：Live Activity 会一直挂着，直到下一条 prompt 的 Stop、SessionEnd 或 3 小时超时。
- 非 Ghostty 终端只能激活 App，定位不到 tab。Perch.app 还没有注册 `perch-terminal://` URL scheme（todo.md 里的这类链接点不开）。
- 点击 / 快捷键的 UI 路径没有自动化测试（只测了 `Click` 映射和 `QueueModel`），改交互要人工回归上面的清单。

## 工作约定（来自用户和 CLAUDE.md）

- 文档用中文；代码注释用英文，和现有代码保持一致。
- 每个清单项一个 commit，Conventional Commits（`feat(app): …` 等），提交前 `swift build && swift test` 必须通过；新行为先写测试。
- 做完一项：勾 `docs/MILESTONES.md` 对应的框，并更新本文进度表；未决问题定下来后同步更新 CLAUDE.md 的"未决问题"。
- 范围守卫：dispatch、stop / cancel、reply、MCP、双向同步、音乐 / HUD 等一律不做（见 CLAUDE.md）。
- 不主动 push；远端操作先问用户。

## M2 提交记录

```
366b75e test: M2 acceptance — CLI to notch ≤ 200 ms
22106c3 feat(app): due_at reminders — system notification and a notch pulse
4e11d1e feat(app): ⌥⇧Space opens quick entry
d0a85e6 feat(app): click to complete, ⌥-click to snooze 30 min, click a notice to keep it
d8c26ec feat(app): expanded notch lists the queue on hover
a1b6d86 feat(app): collapsed notch shows count, colour dot and Live Activity
e608798 feat(app): notch panel over the notch, capsule on screens without one
c06ddf4 feat(daemon): update op and `perch update` for snooze and notice → task
eaa40b2 feat(app): build the notch app with SwiftPM and bundle it as Perch.app
```

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
