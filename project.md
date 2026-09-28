# Perch — 开发路线与进度（交接文档）

> 给接手的 session：先读本文，再读 `CLAUDE.md`（架构铁律）、`docs/MILESTONES.md`（逐项验收清单）、`docs/PRD.md`（产品需求）。
> 本文负责"做到哪了、下一步怎么做、有哪些坑"；验收框以 `docs/MILESTONES.md` 为准，两边进度要同步更新。

最后更新：2026-09-28 · M4 代码完成，等真实会话验收；之后 M5

## 总览

| # | 里程碑 | 状态 | 说明 |
| --- | --- | --- | --- |
| M1 | daemon + CLI + SQLite + watch | ✅ 完成 | 10 项全勾，73 个测试通过 |
| M2 | 刘海 UI | ✅ 完成 | 8 项全勾；CLI → 刘海 均值 11 ms。悬停、点击用户已确认 |
| M3 | Claude Code 被动接入（UserPromptSubmit / Notification / Stop） | ✅ 完成 | 152 个测试；用户在 Ghostty 和 Claude 桌面 App 里实测：变橙、notice、跳回原 tab 都正常 |
| M4 | PermissionRequest + 白名单 | 🔶 代码完成 | 176 个测试；剩重新安装 + 真实会话验收（见"M4 进度"） |
| M5 | Codex 复用同一套 hook 脚本 | ⬜ 未开始 | |
| M6 | Hermes HTTP 接入 | ⬜ 未开始 | HTTP `POST /rpc` 已就绪，只剩容器内实测 |

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
  Sessions.swift         Session / SessionEvent（Live Activity，不入库）
  Hooks.swift            HookInput / HookAdapter（hook 事件 → 请求；PermissionRequest 的 ask / terminal 计划；决定 JSON）
  Allowlist.swift        刘海可批准的范围（tools / bash / protected_paths）
  PermissionPrompt.swift request 显示的完整文本；JSONValue.swift 任意 JSON（tool_input）
  TerminalLink.swift     perch-terminal://<app>?id=&cwd=&bundle=
Sources/PerchClient/   PerchClient.send / watch() → EventStream；BufferedSocket（阻塞式 socket + 读缓冲）
Sources/PerchDaemon/   Daemon（串行队列 + 订阅者 + 过期计时器 + 镜像 + inbox 监听）、Service（各 op）、Store（sqlite）、SessionRegistry、
                       Server / HTTPConnection（Unix socket + 127.0.0.1 HTTP）、Files（MirrorWriter / InboxWatcher）、LaunchAgent
Sources/perch/         CLI：add / ls / get / done / update / respond / rm / watch / session / hook / hooks
  Hook.swift             `perch hook <agent>`：stdin → HookAdapter → perchd；Ghostty 探测；HookLog
  HooksInstall.swift     `perch hooks install|uninstall claude-code`（ClaudeSettings：合并 / 移除 settings.json）
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
- op：`ping / add / list / get / done / respond / remove / update / watch / session_start / session_end / sessions`。
- session（M3，Live Activity）：只在 perchd 内存里，不进 SQLite；`watch` 推 `{"ok":true,"session_event":{…}}`，`EventStream.next()` 只返回 item 事件（老客户端不受影响），`nextPush()` 两种都给。每条消息带观测时间，比该 id 最后一条旧的消息丢弃（async hook 会乱序）；超过 3 小时没结束的 turn 自动清掉。`list` 默认只返回 open + waiting，已按队列顺序排好。
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
| 4.4 | 验收 | ⬜ | 见下 |

### M4 验收步骤

```
scripts/install.sh      # 升级二进制和 App，并把新的 hook（PermissionRequest / PostToolUse*）写进 settings.json
```
- [ ] Ghostty 里让 claude 跑 `npm test`（或 `git status`）：终端显示 "Waiting for Perch…" 转圈，刘海出现 request；点 Allow（或 ⌥⇧A）→ 终端不弹提示，命令直接跑
- [ ] 让它跑 `rm -rf <某个临时目录>`：终端立刻弹原生提示；刘海只有一条"Answer in the terminal · …"，点它回到那个 tab；在终端批准后橙色马上消失
- [ ] 再来一次 `npm test`，不理刘海：20 秒后终端原生提示正常弹出，刘海那条变成"去终端"
- [ ] Deny（⌥⇧D）：Claude 收到 "Denied by the user from the Perch notch." 并继续
- 风险：hook 运行期间终端是否真的只转圈、不同时弹提示框（文档没写死），以实测为准。

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

- inbox 最后一行如果还没写完（没有换行符）就被读到，会被当成一整行吸收。`echo >>` 一次写入没问题。
- inbox 在"读取 → 核对 → 原地重写"之间有微秒级窗口，这期间追加的行可能丢失（已尽量缩小）。
- 从 `.build/` 执行 `perchd install` 会打印提醒：执行 `swift package clean` 后 agent 就会失效。日常使用要先把二进制复制到固定位置再装。
- 测试用的 Unix socket 放在 `/tmp/perch-test-*`：socket 路径上限 103 字节，`/var/folders/...` 太长。
- CLITests 通过 `--test-bundle-path` 找 `perch` 二进制（swift-testing 跑在 `swiftpm-testing-helper` 里，`Bundle.main` 不可用）。
- Perch.app 还不会开机自启（perchd 有 launchd，App 没有）；也没有图标（`actool` 不可用，要做就放 .icns 到 `packaging/`）。
- 展开态高度是估算的（request 按 52 字 / 行算），很长的 request 靠列表滚动兜底。
- `link` 只能打开 URL 和绝对 / `~` 路径；tmux 等终端会话引用没有跳转按钮，等 M3 定机制。
- Esc 打断一轮时 Claude Code 不发 Stop：Live Activity 会一直挂着，直到下一条 prompt 的 Stop、SessionEnd 或 3 小时超时。
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
