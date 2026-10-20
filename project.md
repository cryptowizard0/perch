# Perch — 开发路线与进度（交接文档）

> 给接手的 session：先读本文，再读 `CLAUDE.md`（架构铁律）、`docs/MILESTONES.md`（逐项验收清单）、`docs/PRD.md`（产品需求）。
> 本文负责"做到哪了、下一步怎么做、有哪些坑"；验收框以 `docs/MILESTONES.md` 为准，两边进度要同步更新。

最后更新：2026-10-19 · **M15 dsh（DeepSeek Harness）已合并**（#73：PR #77 / #78 / #79，还没发版）· **v0.4.3 已发布**（Todo tab、Todo 搬进 Reminders、更多列表 / Lists… / Doing、收起态 todo 数、小怪物更多动作）· v0.4.2（事件横幅、小怪物动画）· v0.4.1（Grok、提示音、选显示器）· v0.4.0（零配置安装，#25：PR #30 squash 合并为 `a3558b0`）· v0.3.0 是刘海小怪物（#22 / #23）· v0.2.0 是第一阶段（M1–M8）· 只支持 Claude Code 和 Codex（Hermes 暂不支持，M9 搁置）· `main` 的版本号就是最近发布的版本（现在是 `0.4.3`，2026-10-14 用户定：不再用 `-dev`）· 零配置安装 #25 全部完成并关闭（#26–#29，2026-10-12 验收；v0.3 换 App 升级维护者定不测）；#26 / #27 已随 PR #30 关闭。各步细节见下方"零配置安装 #27 / #28 / #29" · **v0.5 进行中**：Grok（#31 / M11）已完成，PR #33 squash 合并为 `1f83a18`，见下方"M11 进度" · 提示音（#35）已完成，PR #36 squash 合并为 `6c8c3e2`，见下方"提示音 #35" · 多屏选显示器（#37）已完成，PR #38 squash 合并为 `7a88ea3`，随 v0.4.1 发布 · 事件横幅 + 小怪物动画（#39）已完成，PR #40 squash 合并为 `a4262c3`，见下方"事件横幅与小怪物动画 #39" · **Todo tab（M12，#41）进行中**：#42（priority、tab 栏、Todo tab、完成 + 撤销）PR #46 squash 合并为 `c206c27`；#43（弹窗、编辑、删除、文档）在分支 `todo-entry-popup`，等维护者用一天后验收，见下方"Todo tab（M12）" · **Todo 搬进 Apple Reminders（M13，#50）完成**：#51（bridge）、#52（CLI / inbox 经 bridge 写）、#53（日期、✎、大编辑器）2026-10-16 维护者验收通过；#52 / #53 在 PR #54，见下方"Todo 搬进 Reminders（M13）"；只剩两个延迟数字没记到 #50 · 收起态右翼的 todo 图标和数（#56）已完成，PR #57 squash 合并为 `0c267b8`，见下方"收起态右翼的 todo 数" · **更多 Reminders 列表（M14，#66）完成**：#69（数据通路、列表选择、Todo tab 和 CLI 按列表分组）、#70（Lists… 窗口、列表选择器、`--list`）、#71（优先级胶囊、Doing，schema v7）2026-10-19 维护者验收通过，PR #72 squash 合并为 `4e4131c`，#66 已关，见下方"更多 Reminders 列表（M14）"；随 v0.4.3 发布

## 发布

| 版本 | 日期 | 内容 |
| --- | --- | --- |
| [v0.4.3](https://github.com/cryptowizard0/perch/releases/tag/v0.4.3) | 2026-10-19 | Todo tab（M12，#41–#43，PR #46 / #47）、todo 搬进 Apple Reminders（M13，#50–#53，PR #51 / #54）、收起态右翼的 todo 数（#56，PR #57）、小怪物更多动作（#58–#64，PR #65 / #67）、更多 Reminders 列表 / Lists… 窗口 / `--list` / 优先级胶囊 / Doing（M14，#66，PR #72，schema v7）。用户定发 0.4.3（不是 0.5.0）。tag 打在 `b3fbb4c`（`chore: release v0.4.3`），zip sha256 `319b2f89…`（下载回来核对过），cask 改版本在随后的 `chore(cask): perch 0.4.3`（`a70caa5`）；release notes 提醒了 `perch ls` / `todo.md` 的新排序和 schema v7 不能回退；`main` 停在 `0.4.3` |
| [v0.4.2](https://github.com/cryptowizard0/perch/releases/tag/v0.4.2) | 2026-10-14 | 事件横幅、小怪物第二段反应和闲时彩蛋（#39，PR #40）。用户定发 0.4.2。tag 打在 `cece3b8`（`chore: release v0.4.2`），zip sha256 `38856d71…`，cask 改版本在随后的 `chore(cask): perch 0.4.2`；`main` 停在 `0.4.2` |
| [v0.4.1](https://github.com/cryptowizard0/perch/releases/tag/v0.4.1) | 2026-10-14 | Grok Build（#31，PR #33）、提示音（#35，PR #36）、选显示器（#37，PR #38）、后台任务通知不再盖掉 prompt（#32，PR #34）。用户定发 0.4.1（不是 0.5.0），tag 打在 `a58f016`（`chore: release v0.4.1`），zip sha256 `79290e52…`，cask 改版本在随后的 `chore(cask): perch 0.4.1`；`main` 先改回 `0.5.0-dev`，用户看到 `install.sh` 装出来是 0.5.0-dev，定版本统一用 0.4.1，`main` 就停在 `0.4.1` |
| [v0.4.0](https://github.com/cryptowizard0/perch/releases/tag/v0.4.0) | 2026-10-12 | 零配置安装（#25 / #26–#29，PR #30）：拖进 Applications 或 `brew install --cask cryptowizard0/perch/perch` → 打开过 Gatekeeper → 刘海里的设置卡片 Connect；App 自检维护 `~/.perch/bin` / perchd / hook；开机启动；刘海里的 Uninstall；`perch setup` / `perch uninstall`。tag 打在 `8540c56`（`chore: release v0.4.0`），用 `scripts/package-release.sh` 打包，zip 只含 Perch.app（sha256 `de423668…`），cask 改版本在 `42f6005`，之后 `main` 改成 `0.5.0-dev`。发版说明照 `docs/RELEASE-NOTES-TEMPLATE.md` |
| [v0.3.0](https://github.com/cryptowizard0/perch/releases/tag/v0.3.0) | 2026-10-09 | 收起态的圆点换成像素独眼小怪物、按状态动画，进入 Needs you / Failed / Done 时有反应动作（#22，PR #23）；刘海两边按内容收窄。tag 打在 `fed12a8`（`chore: release v0.3.0`），之后 `main` 改成 `0.4.0-dev`。附 `perch-0.3.0-macos-arm64.zip` + `.sha256`（同样只有 arm64、ad-hoc 签名） |
| [v0.2.0](https://github.com/cryptowizard0/perch/releases/tag/v0.2.0) | 2026-10-09 | 第一阶段（M1–M8）：刘海里的 agent 面板，支持 Claude Code + Codex。tag 打在 `4a1df87`（`chore: release v0.2.0`），之后 `main` 改成 `0.3.0-dev`（`cadb7d6`）。GitHub Release 附 `perch-0.2.0-macos-arm64.zip`（`perch` + `perchd` + `Perch.app`，只有 arm64、ad-hoc 签名未公证）和它的 `.sha256` |

预编译包的坑（2026-10-09，用户在另一台电脑装 v0.3.0 的 zip，Codex 会话一直不出现）：**原因是没在 codex 里 `/hooks` 信任**，Codex 静默跳过未信任的 hook。当时 README 的 Install 加了单独的"Codex: trust the hooks"一节和 Troubleshooting 表（v0.4 起 Install 整体换成新流程，见下方"零配置安装 #29"）。每次发版的 release notes 都要带上"在 codex 里 `/hooks` 信任"这一句。Claude Code 没有信任这一步（按官方 hooks / permissions 文档核对，2026-10-09）：用户设置里的 hooks 直接生效、改了会被文件监视自动加载；会让它收不到的是 `disableAllHooks`（项目设置可以覆盖用户设置）、托管设置的 `allowManagedHooksOnly`、`CLAUDE_CONFIG_DIR` 不一致，以及预编译包的隔离标记 / 路径失效。Claude Code 里的 `/hooks` 是只读列表，可以用来确认 Perch 的 8 个 hook 是否生效。

发版步骤（v0.4.0 起，#29）：`Sources/PerchCore/Version.swift` 改成新版本号 → `swift build` + `swift test` → 提交 `chore: release vX.Y.Z` → `git tag -a vX.Y.Z` → 推 main 和 tag → 在 tag 的独立 worktree 里跑 `scripts/package-release.sh`（`dist/perch-X.Y.Z-macos-arm64.zip` 只含 Perch.app，加 `.sha256`，并改好 `Casks/perch.rb` 的 version / sha256）→ 照 `docs/RELEASE-NOTES-TEMPLATE.md` 写 notes（Gatekeeper 的 Open Anyway 和 Codex `/hooks` 两步每次都要有）→ `gh release create vX.Y.Z --verify-tag --notes-file … dist/*.zip dist/*.sha256` → 把 worktree 里改好的 `Casks/perch.rb` 提交到 main（`chore(cask): perch X.Y.Z`；cask 在 release 发布之前指向的 zip 不存在）。发完 `main` 停在这个版本号，不再改成下一个 `-dev`（2026-10-14 用户定，v0.4.0 及以前发完会改成 `-dev`）：从源码装出来的版本号和发布版一致；代价是两次发版之间 main 上的改动也报这个版本号，App 自检按版本判断要不要同步二进制，所以从源码升级要靠 `install.sh`（它跑的 `perch setup --upgrade` 总是拷）。v0.2.0 / v0.3.0 是手动 `bundle-app.sh` + `ditto` 打的，zip 里还有 perch / perchd。版本号只有 `Version.swift` 一处，`perch` / `perchd` 读它，`bundle-app.sh` 去掉 `-dev` 写进 Info.plist。本机只有 Command Line Tools，打不了 universal（x86_64）包。

## 总览

| # | 里程碑 | 状态 | 说明 |
| --- | --- | --- | --- |
| M1 | daemon + CLI + SQLite + watch | ✅ 完成 | 10 项全勾，73 个测试通过 |
| M2 | 刘海 UI | ✅ 完成 | 8 项全勾；CLI → 刘海 均值 11 ms。悬停、点击用户已确认 |
| M3 | Claude Code 被动接入（UserPromptSubmit / Notification / Stop） | ✅ 完成 | 152 个测试；用户在 Ghostty 和 Claude 桌面 App 里实测：变橙、notice、跳回原 tab 都正常 |
| M4 | PermissionRequest + 白名单 | ✅ 完成 | 用户确认验收通过（2026-09-28） |
| M5 | Codex 复用同一套 hook 脚本 | ✅ 完成 | 用户确认验收通过（2026-09-28） |
| M6 | Hermes 接入（改为 shell hook） | ✅ 完成 | 用户确认验收通过（2026-09-28） |
| M7 | 会话状态机（sessions 表、pid 存活检测、Claude Code / Codex hook 映射重写） | ✅ 完成 | #15 状态机 ✅；#16 存活检测 ✅；#17 真实会话验收 ✅（2026-10-08，Hermes 一轮未测） |
| M8 | Agent 面板 UI；刘海 todo UI 下线 | ✅ 完成 | #18 面板 ✅；#19 交互 + todo 下线 ✅；#20 验收 ✅（2026-10-08，用户确认） |
| M11 | Grok Build（#31，v0.5 第一个新 agent） | ✅ 完成 | 363 个测试；2026-10-12 维护者真实会话验收通过，PR #33 合并为 `1f83a18`，#31 已关（见"M11 进度"） |
| M12 | Todo tab（#41：#42 / #43） | 🚧 待验收 | #42 已合并（PR #46）；#43 代码和文档完成，等维护者用一天后验收（见"Todo tab（M12）"） |
| M13 | Todo 搬进 Apple Reminders（#50：#51 / #52 / #53） | ✅ 完成 | #51 bridge、#52 CLI / inbox 经 bridge 写、#53 日期 / ✎ / 大编辑器，2026-10-16 维护者验收通过（见"Todo 搬进 Reminders（M13）"）；App 写入 → `EKEventStoreChanged` 和 iCloud 手机 → Mac 的延迟还没记到 #50 |
| M14 | 更多 Reminders 列表，按列表分组（#66：#69 / #70 / #71） | ✅ 完成 | 605 个测试；2026-10-19 维护者验收通过，PR #72 squash 合并为 `4e4131c`，#66 / #69 / #70 / #71 已关（见"更多 Reminders 列表（M14）"） |
| M15 | dsh（DeepSeek Harness，#73：#74 / #75 / #76，v0.5 第二个新 agent） | ✅ 完成 | 632 个测试；2026-10-19 真模型验收通过；PR #77 / #78 / #79 squash 合并为 `36d20d3` / `e68848f` / `5a2ed8b`，#73 / #74 / #75 / #76 已关（见"M15 进度"） |
| M16 | dsh web 的会话上刘海（#80） | 🚧 待合并 | 代码、测试、文档做完；隔离环境端到端和 2026-10-20 真模型检查都通过，PR #81 等合并（见"M16 进度"） |
| M9 | Hermes 迁到会话模型 | ⏸ 搁置 | 2026-10-08 用户定：先只支持 Claude Code 和 Codex，Hermes 暂不支持。`install.sh` 不再装 Hermes hooks，本机已 `perch hooks uninstall hermes`；适配器和 `perch hooks install hermes` 代码保留，想恢复手动装即可 |

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
| todo | UI 拿掉，底层和 CLI 不动；以后作为独立 tab 回来 | 2026-10-15 回来了：Todo tab（M12，#41） |
| 会话存哪 | SQLite（`sessions` 表） | 推翻 M3 "session 只在内存"的决定；重启后面板原样恢复 |
| 僵尸会话 | pid 存活检测为主（30 秒）+ 24 小时超时兜底 + 手动移除 | |
| 接哪些 agent | Claude Code + Codex；Hermes 暂不显示（2026-10-08 起暂不支持，M9 搁置） | Codex 几乎零成本，还能验证状态机与 agent 无关 |
| 会话与 item 分工 | 状态只在会话里；item 只剩 request | 一个概念只放一处 |
| 交互 | 点整行跳转；Allow / Deny；⌥⇧A / D / O；右键行移除；右键刘海只剩 Quit | |
| 提醒 | 刘海脉冲；2026-10-12 起加提示音（#35，进入 Needs you / Failed / Done 各一种怪兽音效，默认全开）；仍不发系统通知 | 用户要求加提示音，Done 也要 |
| 文案 | 英文 | 和现有 UI、CLI 一致 |

过渡期注意：Hermes 的 waiting / notice 仍会写进 item 表（#19 只停了 Claude Code / Codex 的），但 M8 起刘海不再显示 item（request 除外），所以 Hermes 的审批提示在 M9 前只能在终端 / Telegram 看到。

## 开发环境（重要）

- **本机没有 Xcode，只有 Command Line Tools**（Swift 6.1.2，`Package.swift` 仍是 tools-version 5.9 / Swift 5 语言模式）。
  - 没有 XCTest → 测试全部用 **swift-testing**（`import Testing`、`@Test`、`#expect`）。
  - `xcodebuild` 不可用 → App 用 SwiftPM 编译、`scripts/bundle-app.sh` 组装 `.app`（M2.1 定）。
  - SwiftUI / AppKit 可用：已验证 CLT 能编译运行 `NSPanel` + `NSHostingView`，并读到刘海安全区高度 33pt。Observation / Testing 宏插件也在。
  - `screencapture -x` 可用（有屏幕录制权限）：改 UI 后截图 + `sips -c` 裁剪看效果。**不能合成鼠标 / 键盘事件**（`CGPreflightPostEventAccess` 为 false，System Events 无辅助功能权限）→ 悬停、点击、快捷键只能靠人工或 `PERCH_PIN_EXPANDED=1` 截图。
  - 看窗口位置不需要权限：`CGWindowListCopyWindowInfo` 过滤 owner "Perch"。
- git 提交用 1Password SSH 签名；1Password 锁着时报 "failed to fill whole buffer"，让用户解锁后重试（不要自己关签名）。
  - `codesign` 可用（ad-hoc 签名 `codesign -s -`）。`actool`（Asset Catalog）不可用 → 图标用 `iconutil` 打 icns（见 `scripts/icon/`）。
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
  QueueState             item 快照 + 事件合并（只为找 request）
  QueueConnection        后台线程：watch → list → 事件；离线退避重连 0.5→5 s
  QueueModel             @MainActor ObservableObject：sessions、panel、脉冲、分钟 tick、flash；行 / 快捷键动作 open / remove / respond / openHead / answerHead（jump 由 App 注入）
  Panel / PixelIcon      面板模型（M8）：分组、总色点、Running 数、行文本、request 归属、脉冲；12×12 像素图标
  Jump                   JumpTarget（终端 / URL）、GhosttyScript（focus 的 AppleScript）
  HotKey / RelativeTime
Sources/PerchApp/      AppKit + SwiftUI 壳：NotchPanel / NotchWindowController（悬停、布局、换屏）、NotchView / ExpandedPanel（SessionList / SessionRowView）、
                       GlobalHotKey（Carbon）、Jumper（跳终端）、AppDelegate
packaging/Info.plist · scripts/bundle-app.sh · scripts/measure-latency.sh · scripts/install.sh
Tests/PerchCoreTests/    纯逻辑
Tests/PerchAppCoreTests/ App 纯逻辑
Tests/PerchDaemonTests/  进程内起 daemon（Support.swift 的 TestDaemon）+ 跑真实 perch 二进制（CLITests / AcceptanceTests）；
                         App 连接和 QueueModel 也在这里测（AppConnectionTests / AppModelTests / NotchLatencyTests）
```

## 已定下的契约（M2+ 依赖，改之前先想清楚）

- Wire：Unix socket 上一行一个 JSON；HTTP `POST /rpc` 同一套 JSON。`watch` 先回 `{"ok":true}` 确认，再逐行推 `{"ok":true,"event":{…}}`。**确认之后发生的变化保证能收到**，所以客户端正确做法是：先 `watch()`，再 `list` 拿快照。
- op：`ping / add / list / get / done / respond / remove / update / watch / session_start / session_end / sessions / session_report / session_seen / session_remove / bridge_register / todo_snapshot / todo_ack`（后三个是 Reminders bridge 的，#51 / #52；watch 上给 bridge 推 `todo_op`）。
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
- ~~⌥⇧Space 弹出快速录入~~、~~到期系统通知~~、~~右键 New Task…~~：M8（#19）随 todo UI 下线
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
| 7.3 | 真实会话验收（#17） | ⏸ 部分完成 | 见下；用户暂停，先做 M8 |

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
- 实测（2026-09-28，本机）：Claude 桌面 App 每个会话一个进程（`Claude` → `disclaimer` → `…/claude-code/2.1.x/claude.app/Contents/MacOS/claude`），hook 能找到 → 桌面会话按 pid 清理，不走 24 小时。Codex 桌面 App（ChatGPT.app）所有会话共用一个 `codex app-server` 进程，只有退出 App 才会被清。隔离 perchd 上用"以 `claude` 为名启动的 bash"跑 hook、再 `kill -HUP` 模拟关 tab：20 秒后推 `session.ended`。用户在真 Ghostty tab 里跑 `claude`、关 tab，会话自动消失（2026-09-28 确认）。
- 已知限制：同一个 session id 同时开在两个进程里（另一个 tab `--resume`），以最后上报的 pid 为准，关掉那个 tab 就移除；那个"去终端" waiting item（过渡期的旧 item，#19 下线）不会随会话被清。用 npm 装的 Claude Code（`node …/cli.js`）argv[0] 可能是 `node`（未实测），那样找不到 pid → 走 24 小时兜底。

7.3 的进度（2026-09-29，#17 未关）：
- ✅ install.sh 装好；Codex 的 hooks.json 和 M5 信任时逐字节相同，不用重新 `/hooks` 信任。
- ✅ Claude Code（Ghostty）：Running → Needs you（完整命令）→ 终端批准 → Running → Done；关 tab 后会话消失（#16 时已测）；hook.log 无错误。
- ✅ Done → Idle 10 分钟：本会话（桌面 App）实测 01:09:47 Done → 01:19:47 Idle。
- ❌ **在终端里对权限提示选 No，Claude Code 不发任何 hook**（官方文档：`PermissionDenied` 只管 auto mode；Stop / PostToolUseFailure 都不触发）→ 会话停在 Needs you、刘海一直橙，直到下一条 prompt。和 Esc 打断（#8，会话停在 Running）同一个根因，记在 #8。候选修法：接 Notification 的 `idle_prompt`（waiting / running 时收到 → idle，done 不动），但文档没说它在拒绝 / Esc 后会不会触发，要先实测（`claude --settings /tmp/…` 挂一个只记 Notification 的 hook）。
- 未测：Codex（Running → Needs you → Done、Esc → Idle）、Hermes 一轮。

## M8 进度（Agent 面板）

8.1 面板（#18，2026-09-29）：
- 逻辑都在 PerchAppCore，可测：`Panel`（总色点 = 最紧急状态、Running 数、按状态分组排序、Needs you 会话对应的 request、哪些变化要脉冲）、`SessionRow`（右侧时间、第二行、Needs you 文本拆成"命令 + Answer in the terminal…"）、`PixelIcon`（12×12 点阵，`#` / `.` 字符串）。
- `QueueModel.panel` 由 sessions + 仍在跟踪的 items（只为找 request）算出。脉冲改为会话驱动：进入 Needs you / Failed / Done 各一次，Running / Idle 不脉冲；item 事件不再脉冲（到期提醒仍脉冲，#19 随 todo 下线）。Hermes 会话不进面板（`Panel.hiddenSources`），也不脉冲。
- 排序：Needs you 等得最久在前（`status_at` 升序）；Running 按 `turn_started_at` 升序（新会话排在后面，不跳动）；Failed / Done / Idle 最近的在前。
- 时间：Running = 本轮已跑、Needs you = 等了多久（"<1m" / "4m"）；其余 "just now" / "4m ago"。
- UI：`ExpandedPanel`（`PanelTab` 只有 `.agents`，以后 todo 当第二个 tab）→ `SessionList`（组标题 + 数量）→ `SessionRowView`；Needs you 显示完整文本（命令用等宽字），白名单内才有 Allow / Deny；Idle 整行 45% 透明。收起态左边 `StatusDot`（Running 呼吸、脉冲一圈），右边 Running 数（0 不显示）或离线图标。Live Activity 删掉了。
- 截图（隔离 perchd + `PERCH_PIN_EXPANDED=1`，`screencapture -l <窗口号>` 只截这个 App）：收起态橙点 + 3、只剩 Done 蓝点无数字、只剩 Running 绿点呼吸 + 1；展开态分组、Allow / Deny、"Answer in the terminal"、红色 rate_limit、未知 agent 机器人图标都正常。
- 延迟：`PanelLatencyTests`（hook → 面板模型，5 次最差 < 200 ms，实测整组 0.16 s）；`scripts/measure-latency.sh` 改成 `perch session start` 探针，真 App 均值 10 ms、最差 13 ms。
- 代码审查后改的：有 request 的 Needs you 行显示 **request 自己的文本**（会话 detail 可能已被后来的提问覆盖，Allow 必须对应眼前的命令）；⌥⇧A / D 只回答面板上看得到的 request（`Panel.headRequest`：第一个 Needs you 会话里的 request；没挂会话的 request 永远不会被快捷键批准），⌥⇧O 跳到等得最久的 Needs you 会话；脉冲圈用触发它的状态的颜色（`pulseStatus`），不是总色点的颜色；"Answer in the terminal…" 不截断；高度估算挪到 `PanelLayout`（可测）。
- Running 第二行的 prompt：Claude Code 把 `!cmd`（shell 模式）和 slash 命令包在标签里交给 UserPromptSubmit（`<bash-input>…</bash-input><bash-stdout>…`、`<command-name>/x</command-name><command-args>…`），`HookAdapter.promptLine` 还原成 `$ cmd` / `/x args`。
- 刻意保留：提问类 Needs you 显示 agent 的原话（Notification 的 message），没有才显示 "Waiting for your answer"（PRD 表里只写了后者；原话信息更多，#15 时定的）。
- 已知缺口（M9 前）：Hermes 的会话不进面板、审批 waiting item 也不再显示或脉冲，Hermes 的审批只能在终端 / Telegram 看到。

8.2 交互 + todo 下线（#19，2026-09-29）：
- hook：Claude Code / Codex 每个事件只发 `session_report`，不再发 waiting / notice item，也不再 `done --key` 去关它们；Notification 不再先 `list` 查有没有 waiting（`keep_detail` 已经保证 `permission_prompt` 不覆盖命令）。PermissionRequest：白名单外 / 超时 / 没回应就被关掉，都只把会话写成"完整命令\nAnswer in the terminal[: 原因]"，不再补发"去终端" item；`PermissionPlan.terminal` 只带原因。唯一的 item 是白名单内的 request。Hermes 不变。
- 升级前留下的 waiting / notice item（hook 不再关它们）：perchd 每次启动时 dismiss 掉（`Service.dismissLegacyHookItems`：source 是 claude-code / codex、不是 request、key 以 `<source>:` 开头）。request、Hermes 的 item、人手加的 item 不动（用户定，2026-09-29）。
- App：点整行（Allow / Deny 按钮除外）→ `QueueModel.open(session)`：跳到 `session.link`（`jump` 闭包由 AppDelegate 注入 `Jumper.jump`），Done 的顺带 `session_seen` → Idle；右键行 "Remove from Panel" → `session_remove`；⌥⇧O / A / D 走 `openHead()` / `answerHead(_:)`（和点行同一条路径，可测）。行尾的终端图标只是提示，不再是单独的按钮；命令文本去掉了 `textSelection`，否则点在命令上不会跳（用户定：整行可点优先，不能再从面板复制命令）。右键刘海只剩 Quit Perch。
- 删掉：`QuickEntry`（面板）、`Notifier`、`DueReminders`、`Click`、`RowFormat`（`linkURL` 挪进 `JumpTarget.url`）、`QueueState` 的 summary / signal / nextDue / ordered、`HotKey` 的文本解析 / `description`（只剩 ⌥⇧A / D / O 三个常量）和 `QuickEntryHotKey` 默认值。PerchCore 的 `QuickEntry.parse` 留着（inbox 在用）。
- 测试：`AppModelTests`（真 perchd）点 Done 行 → Idle、点 Running 行只跳转、Remove 后会话消失且下一个事件带回来、⌥⇧O 跳等得最久的会话、⌥⇧A 回答第一个 request；`HookCLITests` / `CodexHookTests` 断言整轮下来除了 request 没有任何 item（`list --all`）。
- 截图（隔离 perchd + `PERCH_PIN_EXPANDED=1`）：Needs you（Codex、`rm -rf dist/` + Answer in the terminal）+ Done 两组正常，`perch ls --all` 空。点击 / 右键 / 快捷键没法合成，留给 #20 人工验收。

8.3 验收（#20，进行中，2026-09-29）：
- ✅ install.sh 装好（#19 之后）；新 perchd 启动时把上一轮旧 hook 留下的 notice dismiss 掉了（只剩 1 条），`todo.md` 显示 "Nothing waiting"。
- ✅ 延迟：`scripts/measure-latency.sh 20`，均值 14 ms、最差 36 ms（预算 200 ms）。
- ✅ 真实会话截图（本机刘海在 MacBook 内屏，5K 外接屏是主屏）：收起态绿点 + 1（这个会话 Running，另一个 Idle 不计数）；展开态另开一个 `PERCH_PIN_EXPANDED=1` 的实例连真实 perchd 截图：Running / Idle 两组、组标题数量、Claude Code 小怪物图标、prompt / 回复首行、Idle 整行变暗都对。
- ✅ PRD 对齐实际实现：审批行 "Answer in the terminal: 原因"、提问行显示 agent 原话、⌥⇧A / D / O 的目标、SQLite 用系统 libsqlite3。
- ✅ 人工（2026-10-08，Ghostty + `claude`，测试目录 `/tmp/perch-m8`，`npm test` 只打印 ok）：
  - Claude 自己给命令加了 `2>&1 | tail -40`：刘海只显示完整命令 + "Answer in the terminal: uses shell operators…"、没有按钮（白名单外的路径）；终端选 Yes 后刘海变蓝。
  - 要求原样跑 `npm test`：刘海出现 Allow / Deny，点 Allow 后终端不弹提示、直接跑完。
- 改了（验收中用户定）：Codex 图标 `>_` 认不出来，换成仿 ChatGPT 的六环花结；`PixelIcon` 支持 24×24 细格（同样 12pt，一格一个 Retina 像素），其他图标仍是 12×12（`08fee1f`）。PRD 原来的"不照描任何 logo"相应改了；开源分发前要再评估这个图标和 OpenAI 商标的距离。
- ❌→✅ 验收发现：Codex 桌面 App（ChatGPT.app）的会话点了不跳。原因：它的 hook 跑在 `ChatGPT.app/…/CodexCLI.app/…/codex app-server` 下，环境里既没有 `TERM_PROGRAM` 也没有 `__CFBundleIdentifier`（Claude 桌面 App 会传），链接是空的。修法：两者都没有时，按 agent 进程的可执行路径（`SystemProcesses.executablePath`，`proc_pidpath`）找最外层 `.app`（`TerminalLink.hostApp`），读它的 bundle id（ChatGPT.app 是 `com.openai.codex`），链接 = 激活那个 App。所有 Codex 桌面会话共用一个 app-server 进程，所以只能激活 App，定位不到具体对话。测试用 `cc` 现编一个放在假 `.app` 里的 "codex"（复制的 /bin/sh 在系统目录外会被杀）。已有的会话要等下一条 prompt 才会换上新链接。用户实测（2026-10-08）：重装后在 Codex 桌面 App 里发一条消息，点 Done 行能跳到 ChatGPT.app 并变灰。
- ✅ 人工其余各项（2026-10-08，用户确认全部通过）：⌥⇧A / ⌥⇧D、20 秒超时交给终端（会话改成 "Answer in the terminal"、按钮消失）、⌥⇧O、点 Ghostty 会话的行跳回原 tab 并变灰、Codex CLI 会话（Running → Needs you → Done、Esc → Idle）、右键 "Remove from Panel" 后下一个事件带回来、右键刘海只有 Quit、全屏 Ghostty 下刘海可见 / 能展开 / 能看到脉冲、关 tab 30 秒内消失。`~/.perch/hook.log` 不存在（hook 从没失败过）。
- 未测：Hermes 一轮（#17 的验收项之一；M8 起 Hermes 不进面板，只确认 hook 还能跑）。
- 待定（用户还没选）：行尾跳转图标区分终端和桌面 App（现在一律是终端图标，悬停提示 "Back to app"）；候选是桌面 App 用单色窗口图标 + "Back to ChatGPT / Claude"（App 名从 bundle 读），或用 App 自己的彩色图标。

## v0.3：刘海小怪物（#22，2026-10-09）

- 用户从 6 个候选（小角怪 / 独眼怪 / 小幽灵 / 史莱姆 / 小蝙蝠 / 毛球怪）里选了**独眼怪**：一只大白眼在 1x 下最好认，表情基本靠这只眼。方案和逐状态动画写在 #22。
- `PerchAppCore/Mascot.swift`：纯函数 `Mascot.frame(mood, time:, reaction:)` → 画布上的格子（`body` / `white` / `dark` / `faint` 四种墨）；画布 15×16pt，精灵 13×13 在 (1, 3)，Idle 的 z 允许往右溢出到 18pt（那时不会有 Running 数）。眨眼放在 4 秒周期的 3.6–3.9 秒：放在周期末尾，静止帧（t = 0）才是睁眼的；长 300ms，比一次重绘间隔（5fps，屏幕取整后最多约 0.22 秒）长，任何采样相位每个周期都能采到（PR #23 Codex review 指出原来 150ms 可能永远采不到，`runningBlinksWhateverTheFramePhase` 覆盖）。
- `PerchApp/MascotView.swift`：`TimelineView(.animation(minimumInterval:paused:))` + `Canvas`，不抗锯齿；fps 为 0 的状态（Failed / Done / 没有会话 / 离线）暂停不重绘。反应由 `QueueModel.pulse` 触发、用 `pulseStatus` 的样子和颜色（取代原来的光环），`@Environment(\.accessibilityReduceMotion)` 下只画 `Mascot.still`。
- 收起态两边的宽度（原来固定 40pt）改成按左边内容算、两边对称（用户嫌宽，2026-10-09）：`NotchGeometry.collapsedWing` = 边距 7 + 小怪物 15 +（间距 3 + Running 数 / 离线图标）+ 4，只有小怪物 26pt、一位数字 37pt、离线 44pt、两位数字 45pt（数字 7.9pt、离线图标 15pt 是实测的）。Running 数从 0 变成 1 时整条会变宽，展开 / 收起本来就是这样换 frame 的。`StatusDot` 只剩展开态每行用（呼吸保留，光环 / 离线参数删掉）。
- 截图验收（隔离 perchd + debug App，`screencapture -l` 截窗口，自写 CGImage 最近邻放大看像素）：六种状态、Needs you 和 Done 的反应、"等你时另一个会话跑完"先蓝色跳再回橙色、离线都对；连拍 8 张：Running 6 种帧、Needs you 4 种、Idle 3 种，Failed / Done 1 种。"减少动态效果"没法在本机切换（系统设置），靠单测覆盖。

## 零配置安装 #27：App 自检与刘海里的设置（2026-10-10）

- **打包**：`scripts/bundle-app.sh` 把 `perch` / `perchd` 放进 `Perch.app/Contents/Helpers`（不放 `Contents/MacOS`：大小写不敏感的盘上 `perch` 和 `Perch` 同名），先签 helper 再签 App。
- **自检**（`PerchAppCore/AppSetup.swift`，同步 I/O，`SetupModel` 放到后台串行队列跑）：只在 App 位于 `/Applications` / `~/Applications` 且没设 `PERCH_HOME` 时干活（`Setup.maintainsInstall`）。版本不同（两个方向）就把 Helpers 里的二进制拷进 `~/.perch/bin` 并重装 launchd（= 重启 perchd）；launchd plist 不在也重装；on 的 agent 的 Perch hook 过期就重写（`perch uninstall` 之后 hook 没了的不自动放回，行里给 Connect）。agents.json 坏了：只同步二进制，不修 hook，显示错误行。
- **App 连的 perchd** 改成 `SetupEnvironment.current.socket`（`$PERCH_HOME` 或 `$HOME/.perch`），和自检装 perchd 的位置一致。正常启动时等于原来的 `~/.perch`；好处是 `HOME=/tmp/x` 的隔离运行完全隔离（`FileManager.homeDirectoryForCurrentUser` 不看 `$HOME`）。
- **纯逻辑**（`PerchAppCore/Setup.swift` 的 `SetupState`，测试在 `SetupPanelTests`）：
  - 首次运行卡片：开发构建以外、卡片没显示过（user defaults `SetupCardShown`，显示时就记下，所以只自动展开一次）、agents.json 没有条目、没有 agent 是 on。列出 notAsked 的 agent（都勾上）；一个都没找到时卡片只说"还没找到"+ OK。Connect 之后显示每个 agent 的结果和剩下的一步（Codex：`/hooks`），Done 关掉。卡片在时不显示设置行。
  - 设置行（会话分组上面，`Panel.sections`）：错误（读不了的 hook 文件 "Can't read ~/…"、写失败、二进制 / perchd 装不上、agents.json 坏了）→ 信任 → "<Agent> found" / "Perch's hooks for <Agent> are missing"（带 Connect）→ "Updated Perch's hooks for <Agent>"。off / notDetected / connected 没有行。右键 Dismiss 只对本次启动有效。错误行跟着最新的报告走（修好后下次展开就消失）；自检自己发现的（二进制 / perchd 装不上、修复写失败）留到下次启动。
  - 右键刘海的 Agents 子菜单（开发构建没有）：勾 = connected / outdated / needsTrust；勾上 = 和 `perch setup <agent>` 一样，取消 = 和 `perch hooks uninstall` 一样（共用 `Installer.disconnect`）。没检测到的 agent 灰掉。展开刘海时重读一次 agents.json 和 hook 文件（CLI 可能改过）。
  - Codex 信任：App 看到 codex 的 `session.updated`，且会话的 `updated_at`（上报时间，perchd 自己的 done → idle / seen 不改它）晚于 `hooks_written_at`（没有写入时间时任何事件都算）→ 立刻去掉信任行、把 `trusted_at` 写进 agents.json。perchd 不变。
- **测试**：`SetupPanelTests`（纯）22 个；`AppSetupTests` 11 个在临时 HOME 里跑真的 `AppSetup` + `SetupModel`（launchctl 是记参数的脚本，Helpers 里的 perch 是打印版本号的脚本）：首次安装二进制并启动 perchd、换新 / 旧版本 App 双向同步并重启、开发构建什么都不碰、Connect 前不改配置、Not now 后的 found 行、修复保留 `--wait`、坏 JSON 不动、agents.json 坏了不出卡片、Connect 写不了出错误行、Agents 菜单开关、信任记录。
- **隔离 HOME 手动验证**（`HOME=/tmp/perch-iso PERCH_LAUNCHCTL=<记参数脚本>`，App 拷到 `$HOME/Applications`，再 `PERCH_HOME=$HOME/.perch perchd run --no-http` 起一个隔离 perchd）：刘海自己展开出卡片、Connect 写了 8 + 6 个 hook（其他设置保留、有 `.perch-backup`）、一个 codex UserPromptSubmit 之后 `trusted_at` 写入；错误行 / 信任行 / 更新行 / found 行 / missing 行都截图看过。**注意**：隔离测试里手敲 `perch hooks install … --settings /tmp/…` 一定要带同一个 `HOME`，否则会把临时路径记进真的 `~/.perch/agents.json`（这次踩过）。
- **本机验收（2026-10-10，用户）**：跑 `scripts/install.sh` 装上新 App 后，展开刘海看到 "Trust Perch's hooks: run /hooks in codex"；在 codex 里发一条消息，这行立刻消失，`agents.json` 写入 `trusted_at`（晚于 `hooks_written_at`）✅。没出首次运行卡片（agents.json 已有条目），符合设计。
- **点击验收（2026-10-10，用户在隔离 HOME 的 App 上亲手点）**：首次运行卡片 Connect → Done（写了 8 + 6 个 hook、有备份、关卡片后出信任行）、Not now、行里的 Connect、右键 Dismiss、Agents 子菜单取消 / 勾上 Codex，全部通过 ✅。#27 验收完成（无刘海胶囊形态没有单独看，展开态和有刘海时同一套布局）。
- **换 App 同步二进制（2026-10-10，用户同意后我在本机做）**：临时把版本改成 `0.4.0-dev.2` 打包进 `~/Applications/Perch.app` 重开 → `~/.perch/bin` 变成 `0.4.0-dev.2`，hook 文件没动；**但 perchd 没起来**：`launchctl bootout` 在旧 perchd 退出前就返回，紧接着的 `bootstrap` 报 "5: Input/output error"（用一个收到 SIGTERM 后 1 秒才退出的假 job 复现），所以 job 没了。`perch setup` 也有同样的潜在问题，之前是碰巧没撞上。修复：`LaunchAgent.install` 在 bootstrap 失败时每 0.2 秒重试、最多 10 秒（`LaunchAgentInstallTests`）。修复后把版本改回 `0.4.0-dev` 再打包重开（降级方向）：`~/.perch/bin` 回到 `0.4.0-dev`、perchd 自动重启（pid 变了，日志是新版本）、会话都在 ✅。

## 零配置安装 #28：开机启动与刘海里的 Uninstall（2026-10-12）

- **先验证 `SMAppService`**：在 /tmp 编了一个 ad-hoc 签名（`TeamIdentifier=not set`）、bundle id `dev.perch.smtest` 的小 App，`SMAppService.mainApp.register()` → status enabled，`unregister()` → notRegistered。所以不需要 launchd 兜底，结论记在 CLAUDE.md 未决问题里。真正注销 / 重新登录的验收要用户做。
- **代码**：`PerchAppCore/LoginItem.swift`（`LoginItemStatus`、`LoginItem`：status / register / unregister / openSettings 四个闭包，`.mainApp` 包 `SMAppService`，只有 `.app` bundle 才会注册）；`AppSetup` 多了 `loginItem` 和 `trash`（默认 `FileManager.trashItem`）、`setOpenAtLogin`、`connect(_:openAtLogin:)`、`uninstall() -> UninstallOutcome`；每份 `SetupReport` 带 `openAtLogin`（只对 maintainsInstall 的 App）。`SetupState`：卡片的 `openAtLogin`（默认 true，Connect 之后不能改）、`closeCard()` 返回要不要注册（仍在 choosing 且勾着）、`loginMenu`、`canUninstall`；Connect 之后卡片结果里多一行 "Perch opens at login" / 去系统设置放行 / "Couldn't turn on Open at Login"。`PanelLayout.cardHeight` 给勾选框多留一行。
- **App 壳**：卡片的勾选框（`CardCheckbox`，和 agent 那几行共用）；右键菜单 Agents 下面是 "Open at Login" 开关和 "Uninstall Perch…"，再下面 Quit；确认用 `NSAlert`（先 `NSApp.activate`，面板不会成为前台）。
- **code review 后的修正**：隔离运行（`$HOME` ≠ 真实 home）会动到真实用户的登录项（SMAppService 不看 `$HOME`），改成那时没有登录项（不显示勾选框 / 菜单项，卸载跳过注销）；卸载进行中再点 Uninstall、Connect、开关登录项都忽略（否则排在卸载后面的 Connect 会写指向已删的 `~/.perch/bin/perch` 的 hook）。已知小限制：右键菜单的登录项状态是最近一次报告的（启动、操作后、每次展开刘海时重读），在系统设置里改了之后不展开就直接右键，可能还是旧的。
- **测试**：`SetupPanelTests` +6（纯）；`AppSetupTests` +11（临时 HOME，假 LoginItem / trash）：卡片 Connect 勾着就注册、不勾不碰、Not now 也照框办、注册失败写进卡片、菜单开关和 requiresApproval 打开设置、卸载删 hook / launchd / bin 留数据并注销 + 进废纸篓、清不掉的 hook 文件照样走完、删不掉 `~/.perch/bin` 时 App 留着且仍注册、开发构建不能卸载、隔离运行不碰登录项、卸载后其他操作都被忽略。`AppSetupTests` 原来在主线程上 inline 跑磁盘 / 进程（合计约 7 秒），加了测试后把同时跑的 `NotchLatencyTests` / `PanelApprovalTests` 挤超时；现在用 `SetupModel` 自己的后台队列 + `await settle()`，主线程空出来，全套 341 个测试 ~10 秒。
- **截图**：隔离 HOME（`HOME=/tmp/perch-iso28 PERCH_LAUNCHCTL=<记参数脚本> PERCH_PIN_EXPANDED=1`）里卡片显示三行勾选（Claude Code / Codex / Open at login），高度合适。隔离运行会往真的 `dev.perch.app` defaults 写 `SetupCardShown`，看完删掉了。
- **待用户手动验收**：勾着 Open at login 注销再登录 Perch 在跑、登录项里有它、菜单里取消后消失；隔离安装上点 "Uninstall Perch…" 删掉 hook / launchd / `~/.perch/bin`、留 `~/.perch`、App 进废纸篓。

## 零配置安装 #29：Homebrew、文档、验收（2026-10-12）

- **homebrew/cask 政策（核对过）**：2026-09-01 起官方仓库停用过不了 Gatekeeper 的 cask（`disable! because: :fails_gatekeeper_check`），`--no-quarantine` 已删。本机 brew 7.0.6 源码里 Gatekeeper 检查（`spctl --assess`）只在 `cask/audit.rb`，安装流程不查 → 自建 tap 能装未公证 App，但一定带隔离标记。
- **tap 放在本仓库**（用户定，不建 homebrew-perch）：`brew tap cryptowizard0/perch https://github.com/cryptowizard0/perch` + `brew install --cask cryptowizard0/perch/perch`；代价是 tap 克隆整个仓库（13 MB）。
- **tap 信任（2026-10-12 发现）**：brew 7 默认要求信任第三方 tap，短名字 `brew install --cask perch` 会被拒绝（本地 tap + 隔离 HOME 用 `brew info` 实测：短名字 "Refusing to load cask … from untrusted tap"，完整名字正常）；用完整名字安装 / 升级时 brew 自动信任这个 cask。README、cask 注释、发版说明模板都改成完整名字。
- **隔离标记实测**：带标记的 ad-hoc `perch` 在终端执行 → SIGKILL（exit 137），去掉标记正常；bundle 外带标记的 shell 脚本能跑；但未批准的 bundle 里任何东西（包装脚本、哪怕去掉了标记的文件）都被杀，Gatekeeper 评估整个 bundle。这几次被拦时屏幕上大概弹了"无法验证"对话框，测试用的 App 随后被系统删掉了（不在废纸篓）——之后没有再试。**已确认（2026-10-12，维护者本机用真实的 v0.4.0 cask）**：Open Anyway 批准 App 之后，PATH 上的 `perch`（包装脚本）能跑。
- **cask**（`Casks/perch.rb`，`brew style` 通过）：`app "Perch.app"`；`binary` 链包装脚本 `Contents/Resources/bin/perch`（`packaging/perch-path.sh`，`PathWrapperTests` 2 个测试）；`uninstall quit:` + `/bin/sh -c` 跑 `~/.perch/bin/perch uninstall`；`zap` 跑 `uninstall --purge` 并 trash `~/.perch` 和偏好设置。本地 tap + `file://` zip + 隔离 HOME 实测：安装、链接、uninstall 脚本收到 `uninstall`、zap 收到 `uninstall --purge`、链接删除都对。踩坑：`HOMEBREW_NO_INSTALL_FROM_API=1` 会让 brew 去克隆整个 homebrew-core，别设。
- **`install.sh`** 改成和下载一样的路径：打包 App → `~/Applications` → 打开（首次运行走卡片，不再替用户 Connect）；已经装过（`~/.perch/bin`，或 `~/.local/bin` 里 v0.3 的真二进制）时跑 App 里的 `perch setup --upgrade`（新加的，只拷二进制、重启 perchd、修已连接 agent 的 hook，不连新的）；`APPDIR` 不是 Applications 文件夹或设了 `PERCH_HOME` 时直接报错（否则 App 什么都不装，半装状态）。
- **code review 后的修正**：brew 在 upgrade / reinstall 时也会跑 uninstall 的 `script`（brew 7 源码：`UPGRADE_REINSTALL_SKIP_DIRECTIVES = [:signal]`），原来的 cask 每次 `brew upgrade` 都会 `perch uninstall` 断开所有 agent；现在脚本看父进程命令行跳过 upgrade / reinstall，本地 tap 实测 upgrade / reinstall 不调、uninstall 调。zap 去掉了永远不会生效的脚本。`linkOldBinaries` 每次启动都做、失败单独报。`package-release.sh` 检查版本号非空、arm64、cask 真的改上了。
- **待验收时留意**：`brew uninstall` 不注销登录项（只有刘海里的 Uninstall 会），App 删掉后 系统设置 → 登录项 里是否还留着一条。
- **App 自检**同步二进制时也做 `linkOldBinaries`（v0.3 换 App 就能升级，`aV03InstallIsMigratedByReplacingTheApp`）。
- **文档**：README 的 Install（Homebrew / 下载 → Gatekeeper → Connect → Codex 信任）、perch 在终端、升级、卸载（菜单 / brew / CLI）、源码安装、Troubleshooting 全部重写；`docs/RELEASE-NOTES-TEMPLATE.md`；`scripts/package-release.sh`；MILESTONES 新增 M10。
- **v0.4.0 已发布**（2026-10-12）。
- **维护者本机 brew 验收（2026-10-12）**：tap 早在 PR #30 合并前就克隆过，停在旧 `main`、没有 cask，而且已经 tap 过时再跑 `brew tap` 不会更新（`git -C <tap> pull` 或 `brew update` 才行）。之后的步骤：
  - `brew install --cask cryptowizard0/perch/perch` 输出 "Trusted cask"，App 进了 `/Applications`，`perch` 链到 `/opt/homebrew/bin`；
  - 批准之前 `/opt/homebrew/bin/perch --version` 被杀（`killed`），并弹出"未打开 Perch / 移到废纸篓"对话框；
  - `open` App → 系统设置 Open Anyway → 隔离标记从 `0381` 变成 `03c1`（用户已批准位 0x40）；
  - App 自检把 `~/.perch/bin` 从 `0.4.0-dev` 同步到 `0.4.0` 并重启 perchd，会话都在、hook 没动；
  - 批准之后 `/opt/homebrew/bin/perch --version` → `0.4.0`，`session ls` 正常。
  - 注意：这台机器上 `~/.local/bin` 在 PATH 里排在 `/opt/homebrew/bin` 前面，直接敲 `perch` 走的是 `~/.local/bin/perch` 链接；两者最后跑的都是 `~/.perch/bin/perch`。
- **维护者确认（2026-10-12）**：换成 brew 装的 App 之后，本机验证通过：右键菜单的 Open at Login、会话照常显示。
- **体验问题**：装完先在终端敲 `perch`，用户看到的是 Gatekeeper 的"移到废纸篓"对话框，而不是"先打开一次 App"的提示。
- **第二台 Mac 验收（2026-10-12，维护者）**：那台是 Intel（x86_64），v0.4.0 只有 arm64，cask 的 `depends_on arch: :arm64` 拒绝安装（符合预期；brew 在 `/usr/local`）。改为从源码 `scripts/install.sh` 安装（`main`，`0.5.0-dev`，全新的 `~/.perch`），维护者报告全部通过：
  - 设置卡片 → Connect（卡片上直接有 Claude Code 和 Codex）→ Claude Code 会话出现；
  - Codex 信任行出现，`/hooks` 之后消失，Codex 会话出现；
  - 登录项里有 Perch，注销再登录后刘海回来，菜单里取消 / 勾上 Open at Login 生效；
  - 刘海里的 Uninstall Perch… 删掉 hook / launchd / `~/.perch/bin`，保留 `~/.perch`，App 进废纸篓；
  - 补测"后装 Codex"出现 "Codex found · Connect"（藏起 `~/.codex` 重装后放回）。
  - 源码安装测不到 Gatekeeper / zip / brew。
- **维护者本机的最终验收（2026-10-12）**：先把 `~/.perch` 备份到 `~/perch-backup-20261012`。
  - **真实的 `brew uninstall`**：删了 Claude Code 8 条 / Codex 6 条 hook、launchd agent、`~/.perch/bin` 和 `~/.local/bin` 的链接，保留了 `~/.perch`。
  - **`brew install` 后不打开就 `brew uninstall --zap`**：uninstall 脚本什么都没做（没有 `~/.perch/bin`），`~/.perch` 和偏好设置 plist 进了废纸篓，`defaults` 里 `dev.perch.app` 域也没了。
  - **Chrome 下载的 zip**（带隔离标记）→ 拖进"应用程序"→ 仍要打开 → 设置卡片 → Connect：8 + 6 条 hook、`~/.perch/bin` 是 0.4.0、perchd 在跑；Codex 的 `trusted_at` 晚于写 hook 的时间。
  - 卸载后登录项里会不会留一条，没有报告。
  - v0.3 换 App 升级不测（维护者定）。
  - #29 / #25 关闭。
- **当时还没验证的**：
  - 干净账户上用预编译 zip 走完整流程（Gatekeeper 只在维护者本机的 brew 安装上走过，卡片只在源码安装上看过）；
  - 真实环境的 `brew uninstall` / `--zap`（目前只在本地 tap + 隔离 HOME + 假 perch 上测过）；
  - 真正装着 v0.3 的机器只换 App 升级（目前只有单元测试，以及本机 `0.4.0-dev` → `0.4.0` 的替换）。
  这几项要一台 Apple silicon 的 Mac。
- **Intel**：要支持的话得出 x86_64 / universal 包；之前"Command Line Tools 打不了"的结论没试过 `--triple x86_64-apple-macosx14.0` 交叉编译，可以先试。

### M2 协议扩展：`update`（已实现）

- op `update` + `id` + `patch`（`title` / `kind` / `due_at` / `clear_due`，JSON snake_case），只改给了的字段；内容不变不发事件。
- `kind` 只能在 task ↔ notice 之间切；notice 转 task 时清掉 `expires_at`（否则会按 notice 的时间被 dismiss）；request 的 kind 不能改，也不能改成 request。
- CLI：`perch update <id> [--title …] [--kind task|notice] [--due …] [--no-due] [--json]`。推迟 30 分钟 = `--due +30m`（从现在起算，不是从原 due 起算）。

## M11 进度：Grok Build（#31，2026-10-12）

v0.5 接更多 agent（#24）的第一个，用户 2026-10-12 定先做 Grok（#24 原来排第 7）。分支 `feat/grok`，5 个提交：

| 提交 | 内容 |
| --- | --- |
| `7eb2ecf` | 除 `grok` 外的适配器看到 `GROK_HOOK_EVENT` 就退出（Grok 默认跑 `~/.claude/settings.json` 的 hook，payload 带 `session_id`，能解出来，会多出没有 pid 的 claude-code 会话） |
| `e518d44` | 状态机：报告可带 `turn_id`，别的轮的 stop / failure / interrupt 丢掉（只存 `SessionRegistry` 内存，不动 schema）；新 kind `settle` |
| `b19f450` | `perch hook grok`：`HookInput` 两种 key 名都认；`HookAdapter.grok` 映射；`AgentProcess` 认 `grok` / `agent`；`HookSettings.grok` |
| `8773770` | 安装：`Setup.agents` 加 Grok；按 agent 目录检测（`ConfigLocation.agentDirectory`）；`HookFile.ownsFile`（不写备份、空了删文件）；setup 测试清掉 `GROK_HOME` |
| `b923bb2` | 刘海：Grok 图标（斜线穿过的圆环）和名字 |

**实测（grok 1.0.50，临时 `~/.grok/hooks/perch-spike.json` 记录 stdin / 环境 / 进程链，headless + `expect` 驱动 TUI，测完已删，`~/.grok/config.toml` 没动）：**
- payload 是 camelCase，只有 `session_id` / `hook_event_name` / `permission_mode` / `transcript_path` / `tool_name` / `tool_input` / `tool_use_id` 有 snake_case 副本；`lastAssistantMessage`、`promptId`、`reason`、`notificationType` 只有 camelCase。prompt 字段就叫 `prompt`。
- hook 的父进程就是 `grok`（headless 和 TUI 都是，`sh` 直接 exec 脚本）。leader 模式默认关。
- `Notification` `permission_prompt` 和 PreToolUse 几乎同时发（60 ms），原话只有 "Tool permission requested"。本机 `permission_mode = "always-approve"`，测权限要加 `--permission-mode default`；`echo` 这类安全命令不弹框。
- 关掉提示框（Ctrl+C）→ `StopCancelled` `permission_cancelled`；跑到一半 Ctrl+C → `user_interrupt` + `cancelTrigger: ctrl_c`；**模型还没开始就 Ctrl+C：什么都不发**（prompt 放回输入框），只有约 1 分钟后的 `idle_prompt` 能兜底。
- 会话结束：`SessionEnd` + 一次 `Stop`（`reason: shutdown`）；关掉 pty 也发。
- `perch hook grok` 约 7 ms（裸 `sh` 3 ms），所以前台跑 PostToolUse 没问题。

**决定（2026-10-12，用户确认方案）：** runtime 停下（`max_turns` / `no_progress`）算 Failed；装 `idle_prompt` 兜底，但只改 Running / Needs you；不装 PreToolUse；Grok Bot.app 不管；轮次只存内存。

**已知限制：** Needs you 不显示命令（Grok 不给）；刘海永远不能批准 Grok；开了 leader 模式时会话共用 leader 进程，pid 检测只在 leader 退出时清；Grok Bot.app 的会话不显示。

**待做：**
1. ~~真实会话验收~~ ✅ 2026-10-12 维护者本机通过：`APPDIR=/Applications scripts/install.sh` 装上这个分支（本机的 Perch 在 /Applications，zip 装的，不是 brew）→ 设置行 "Grok found · Connect" → Ghostty 里 `grok --permission-mode default` 走完 Running → Needs you → 终端批准 → Running → Done → Ctrl+C → Idle → 关 tab，断开后 `perch.json` 被删。
2. ~~PR 合并后关 #31~~ ✅ 2026-10-12 PR #33 合并（`1f83a18`），#31 已关。
3. 可选的后续：装一个 PreToolUse 记下命令（每次调工具约 7 ms），让 Needs you 显示完整命令。要在状态机里加"记下待批准的命令但不改状态"的报告，先问用户。

## 提示音 #35（2026-10-12）

用户要加提示音，Done 也要响，声音要和小怪物相关。决定（用户确认）：三种状态默认全开；不发系统通知；声音自己合成。

- 触发点就是脉冲：`QueueModel.handle` 里 `Panel.pulses` 为真时问 `Chime`。所以连接 / 重连时的 snapshot、Running / Idle、Hermes、状态没变都不响，启动不会一串响。
- `PerchAppCore/Chime.swift`：`ChimeSound`（状态 → 声音、紧急程度、资源名、没有 bundle 时的系统声音 Glass / Basso / Tink）、`ChimeSettings`（user defaults：`Chimes`、`ChimeNeedsYou` / `ChimeFailed` / `ChimeDone`、`ChimeVolume` 默认 0.6，只能 `defaults write`）、`Chime`（1 秒内只放更紧急的；同一会话同一种声音 10 秒冷却；立刻播放，不为合并而等）。
- `PerchApp/ChimePlayer.swift`：`NSSound`，启动时预载 `Contents/Resources/Sounds/*.wav`。右键刘海 → Sounds：总开关 + 每种状态一个勾，勾上时试听；所有构建都有（不是 setup）。
- 音效：`scripts/sound/make-sounds.swift` 用代码合成（窄脉冲波当"嗓子"、滑音、颤音、固定种子的噪声，所以每次生成的文件完全一样），`scripts/sound/make-sounds.sh` 写到 `packaging/sounds/`（提交），`bundle-app.sh` 拷进 App。时长对齐小怪物的反应动作：
  - Needs you `needs-you.wav`（0.7 s）"Mrrp? Mrrp?"：两声带卷舌颤音、往上滑的叫唤，第二声更高，一跳一声。
  - Failed `failed.wav`（0.5 s）"Uh-oh… bzzt"：两个往下掉、发抖的音，然后天线短路的滋啦声。
  - Done `done.wav`（0.6 s）"Bwip! hehe ✨"：一跳的上滑音、两声咯咯笑、一个高音闪光。
- 已知限制：专注模式 / 勿扰不会让它静音（是声音不是通知；读 Focus 状态要 `INFocusStatusCenter` + 授权，先靠总开关）；没有"你正看着那个终端就不响"。
- 2026-10-12 维护者用 `afplay` 听过三段，`APPDIR=/Applications scripts/install.sh` 装到本机，定"先这样"，开 PR。
- ✅ 2026-10-13 PR #36 squash 合并为 `6c8c3e2`，#35 已关。以后想调声音就改 `make-sounds.swift` 重新生成。

## 选显示器 #37（2026-10-14）

用户双屏（外接 U2701B 是主显示器，内建屏开着放右边），面板一直在内建屏的刘海上，看不到。用户选"右键加 Display 子菜单"（另一个方案是跟着当前菜单栏 / 焦点走，会在两块屏之间跳，没选）。

- 右键刘海 → Display：Automatic（默认，原来的规则：有刘海的屏，没有就 `NSScreen.screens.first`）、Main Display（带菜单栏的那块，换工位接不同显示器时有用）、每块连着的屏一项（`localizedName`，同名的加 " (2)"）。钉住的屏没连上时菜单里留一项 "<名字> (not connected)"（打勾、灰掉），面板退回 Automatic，插回来（`didChangeScreenParametersNotification` 重新布局）就回去。所有构建都有（不是 setup）。
- 存在 App 的 user defaults：`Display` = `automatic` / `main` / 显示器 UUID（`CGDisplayCreateUUIDFromDisplayID`，重启、重插都不变；`CGDirectDisplayID` 会变），`DisplayName` 记名字。缺失或读不懂 = Automatic。
- `PerchAppCore/Display.swift`（纯逻辑，`DisplayTests`）：`DisplayChoice`（选屏、读写 defaults）、`DisplayScreen`、`DisplayMenu`。`NotchModel` 持有选择和当前屏幕列表，`NotchWindowController.layout()` 按它选屏，`AppDelegate` 读写 defaults。
- ✅ 2026-10-14 维护者手动点过菜单、重启后保持；PR #38 squash 合并为 `7a88ea3`，#37 已关，随 v0.4.1 发布。
- 2026-10-14 实测（`-Display <值>` 参数，只对那次进程生效）：Automatic / 内建屏 UUID → 内建屏刘海；`main` / U2701B 的 UUID → U2701B 菜单栏正中的胶囊；没连接的 UUID → 退回 Automatic。右键菜单本身要人工点（不能合成鼠标事件）。

## 事件横幅与小怪物动画 #39（2026-10-14）

用户嫌收起态右边空着，想加滚动文字或动画。讨论后定：**不做常驻滚动**（余光里一直动的东西会稀释橙色信号，也和"收起态最简、两边收窄"的决定冲突），只在脉冲那一刻弹事件横幅；"等你数"不做；小怪物扩展"反应更丰富"和"闲时小彩蛋"（没选"横幅由它带出来"和"悬停互动"）。

- **横幅**（`PerchAppCore/Banner.swift`，`BannerTests`）：和脉冲 / 提示音同一时机（`Panel.pulses`）。右翼伸出来，显示项目名（状态色、半粗）+ 一行：Needs you 是命令或问题（`SessionRow.needsYou` 去掉 "Answer in the terminal"），Failed 是 `error`，Done 是回复首行，没有就用状态名。内容最宽 220pt，放得下停 4 秒；放不下先停 1.2 秒、按 40pt/s 滚一遍到末尾、再停 1.5 秒（最长 12 秒），不循环。更紧急的盖掉不紧急的（Done 不会盖住等你的命令），同级或更紧急的替换；它那个会话离开这个状态或被移除就提前收起；刘海展开时没有横幅（`QueueModel.showsBanners`），展开期间的事件也不留到收起后。"减少动态效果"下不滚、尾部省略号、右翼不做动画。
- 布局：`NotchModel.leftWing` / `rightWing`，`NotchWindowController.layout()` 算目标宽度。右翼变宽时先把窗口放宽，再在 SwiftUI 里给黑色形状做 0.3 秒动画；变窄时形状先收，窗口等动画做完再收窄（`shrinkingFrom`）。没有刘海的屏上，胶囊往右伸长。宽度用 `BannerView.contentWidth`（NSAttributedString 量），`QueueModel.measureBanner` 拿它算停留时长。
- **反应**（`Mascot.swift`）：前半段和原来一样（和提示音对齐），后面再接一段。Needs you 1.3 秒：两跳之后头右边冒 "!"、天线快闪。Failed 1.6 秒：抖完侧躺在地上（精灵转 90°）、冒烟，再一跳站起来。Done 1.5 秒：跳完撒三色彩纸（`Ink.confetti0…2`），左右手轮流举。反应和彩蛋可以画到画布外 `Mascot.margin` = 6pt（刘海高 32pt 上下有空；22pt 的胶囊会裁掉一点烟和彩纸）。
- **闲时彩蛋**：Idle 或没有会话（且 perchd 在线）时，每 240 秒随机来一个：打哈欠伸懒腰 2.4 秒、醒来左右张望 2.6 秒、吹鼻涕泡 2.8 秒（泡泡破了被吓醒一下）。时间和种类是参考时钟的纯函数（`Mascot.nextQuirk(after:)`，按周期号做 hash），没有状态、可以测；`MascotView` 用 `.task` 睡到下一次，播的时候按 14fps 重绘，平时 Asleep 照旧 0fps。"减少动态效果"下不播。
- 验证：392 个测试通过。隔离 perchd + debug App 截图（本机内建屏没刘海可用，是 5K 屏的胶囊）：Needs you / Done 横幅、长回复滚到末尾后收起（截到收窄中间那一帧）、Failed 侧躺、打哈欠都对。跑全量测试时偶发过一次 signal 11（重跑通过，没复现，看起来和这次改动无关）。
- ✅ 2026-10-14 维护者用 `scripts/install.sh` 装到 ~/Applications 实测通过；PR #40 squash 合并为 `a4262c3`，#39 已关，随 v0.4.2 发布。

## Todo tab（M12，#41 / #42 / #43，2026-10-15）

用户 2026-10-15 做了一轮设计评审，全部决定记在 #41（设计不写进单独的 docs/*.md，写在 issue 里）。拆成两个纵向切片：#42 → #43。完整行为见 `docs/PRD.md` 的"Todo tab"，这里只记实现和坑。

- **#42**（PR #46 → `c206c27`）：`ItemPriority`，schema v4（`items.priority`），`perch add|update -p`，`queueOrdered` 把 open task 按优先级排；`PanelTab`（Agents 优先的打开规则）、`Panel.attention`（橙 / 红点）、`TodoList`（分组、摘要）；`QueueModel` 管 tab、待完成（`completionDelay` 默认 3 秒，`DispatchWorkItem`，收起后照样提交）。快照多拉一次 done 的 task，只为区分 "All clear" 和 "Nothing to do yet."。展开时条带换成 `TabStrip`；切 tab 时 `NSAnimationContext` 0.15 秒改窗口高度。`PERCH_PIN_TAB=todo` 配合 `PERCH_PIN_EXPANDED=1` 截 Todo tab。
- **#43**（分支 `todo-entry-popup`）：`TodoEditor`（添加 / 编辑、标题、优先级、Tab 轮换、空白不提交）放在 `QueueModel.editor`；`submitEditor` 添加后保持打开、清空、回到 Normal，编辑发 `update` 后关闭；`delete` 立刻 `rm`；面板展开时 `item.added` 的 task 高亮 1 秒（`highlighted` / `highlightDuration`）；正在编辑的待办没了（done / rm / 离线）弹窗自己关。弹窗是 `PerchApp/TodoPopup.swift`：M2 快速录入的不激活 App 的 key panel（从 git 历史 `4386353^` 拿回来），`sendEvent` 里截 Tab / Shift-Tab / Esc（输入法组字时不截）；从面板打开时 `NotchModel.held` 让面板不因悬停离开而收起，弹窗关掉后指针不在面板上就照常收起。`HotKey` 的文本解析和 `QuickEntryHotKey` 从 M2 拿回来（`HotKey.quickEntry`）。
- 测试：`TodoModelTests` / `TodoEditorModelTests`（QueueModel + 进程内 perchd）、`TodoListTests` / `PanelTabTests` / `TodoEditorTests` / `HotKeyTests`（纯函数）、`PriorityCLITests`（真实 `perch`）、`StartupTests.migratesAV3DatabaseToNormalPriority`。
- 坑：perchd 的 `created_at` 精确到秒，同一秒加的待办在组内按 id 排；测顺序的用一步一秒的假时钟（`SteppingClock`）。所有 `@MainActor` 测试共用主线程，全量并行跑时 200 ms 的延迟测试偶尔超（`cliToNotchModelUnder200ms` 以前就有），所以 #42 没有另加进程内的 200 ms 测试，而是让这个验收测试改加 High 待办。
- 截图（隔离 perchd + `PERCH_PIN_EXPANDED`，本机只有无刘海的外接屏，是胶囊样式）：两个 tab、三种弹窗位置都对。悬停、点击、键盘焦点、全局快捷键只能人工验。

## Todo 搬进 Reminders（M13，#50 / #51 / #52，2026-10-16）

设计在 #50（父 issue）和三个切片 #51 → #52 → #53。完整行为见 `docs/PRD.md` 的"同步"和"Todo tab"里的 Reminders 一节，这里只记实现和坑。

- **#51 bridge**：
  - 接缝：`PerchAppCore/Reminders.swift` 的 `RemindersStore`（@MainActor 协议）是通往 EventKit 的唯一接缝，`RemindersBridge` 管权限、找列表（记下的标识符存在 defaults 的 `RemindersList.<名字>`）、写；`RemindersState` 是 Todo tab 的状态和文案。`PerchApp/EventKitReminders.swift` 是薄实现（授权后换一个新的 `EKEventStore`，旧的看不到列表）。
  - 线上协议：`watch` 的确认带 `watcher`（订阅 id）；`bridge_register` / `todo_snapshot` 是普通请求，带这个 id。bridge 的生命期就是它的 watch 连接，断开时 perchd 在 watch 上推 `{"bridge":false}`（`Push.bridge`），别的 App 收到就报名。
  - perchd：`Daemon` 记 bridge；`Service.applySnapshot` 对比缓存（`todo_refs` 里有的 item 就是缓存的 todo）发 added / updated / removed。引用（短 id ↔ `calendarItemExternalIdentifier` ↔ key）从不删，提醒回来时短 id 不变。缓存的 item：source `reminders`，`meta.reminder` 是外部标识符（bridge 写的时候靠它找提醒）。`Service.isTodoShaped`（open / done 的 task）的写一律拒绝，`Daemon.absorbsInbox = false` 让 inbox 的行留在文件里，两处都等 #52。
  - App：`QueueModel.connect(client:reminders:)`；有权限且找到列表就报名，是 bridge 时 Todo tab 的写直接调 `RemindersBridge`，写完立刻发快照（一次只发一个，读的时候又有变化就再读一次）；不是 bridge 的 App 照旧发请求给 perchd（#51 里会被拒绝）。列表被删时 bridge 发空快照；没权限时不发，缓存不动。面板展开时重看一次权限（系统设置里撤销不一定有通知）。
  - 签名：`scripts/bundle-app.sh` 用 `--requirements '=designated => identifier "dev.perch.app"'`，`codesign -d -r-` 能看到。
- 测试：`RemindersBridgeTests` / `RemindersStateTests`（进程内 perchd + 真 `QueueModel` + `FakeRemindersStore`，手机那边用 `phone…` 方法），`TodoModelTests` / `TodoEditorModelTests` 改成走假 Reminders，`TodoCLITests`（真实 `perch`），`ServiceTests.snapshotsReplaceTheCache` / `todoWritesAreRefused`，`WatchTests.watchersHearWhenTheBridgeComesAndGoes`，`StartupTests.migratingToV5DropsTheOldTodosOnly`。CLI 测试要缓存的 todo 时用 `TestDaemon.bridge(_:)`（线上的假 bridge）。原来往 perchd 加 open task 的管道测试改用等待中的 task 或 notice；五个 inbox 吸收测试先 `.disabled`，#52 打开。
- 坑：假 Reminders 默认不为 App 自己的写发变化通知（`notifiesOwnWrites`），这样测试能证明 bridge 写完自己发快照。`FakeRemindersStore` 是 @MainActor，不能当非隔离函数的默认参数。
- 已知限制：bridge 的权限被撤销时它仍是 bridge（缓存停在撤销前），别的有权限的 App 要等它退出才能接手；刚连上、`bridge_register` 还没回来的一瞬间，刘海里的写会被 perchd 拒绝（闪一下错误，不丢数据）。HTTP 上不能当 bridge，HTTP 的 watch 也收不到 bridge 来去。
- 没做（要人）：真 Mac + iPhone 的验收（Connect、双向、重新编译后权限还在）、两个延迟（App 写 → `EKEventStoreChanged`、iCloud 手机 → Mac）记到 #50 的评论。本机不能合成点击，Connect 弹窗要人点。`x-apple-reminderkit://` 深链接和"只设时间会不会提醒"的 spike 属于 #53。
- **#52 CLI / inbox.md 经 bridge 写**：
  - 线上协议：todo 写由 `Service.planTodoWrite` 判断（`.local` 照旧 `handle`；`.answer` 直接回答，比如同 key 内容一样；`.bridge(TodoWrite)`）。`Daemon.perform` 在队列上把 `TodoOperation` 推到 bridge 的 watch sink（`Response.todoOp`），**离开队列**等信号量（`bridgeTimeout` 默认 2 秒，`TestDaemon(bridgeTimeout:)` 可改）。bridge 回 `todo_ack`（`Request.ack`）时 `recordTodoWrite` 记引用和 key（promote 的本地 item 删掉，引用沿用它的短 id），等**下一份**快照再用 `todoWriteAnswer` 回答；超时的写留在 `pendingWrites` 里，所以晚到的 ack 照样记 key；bridge 断开时全部失败。
  - App：`QueueModel.applyTodo` 用 `RemindersBridge.apply` 写，ack 放进 `acksDue`，下一次读快照开始时取走、读完先发 ack 再发快照（同一个串行 actions 队列），这样 perchd 回答时缓存一定已经有这次改动。写失败立刻回带 error 的 ack（列表没了是 "Perch list not found"）。收到 `todo_op` 就当自己是 bridge（`bridge_register` 的回答可能还在路上）。
  - 字段：`ReminderChange` 挪到 PerchCore（线上要用），加了到期（`dueDateOnly`、`clearDue`）和 URL（`clearURL`）；`RemindersStore.createReminder(inList:_:)` 改成收 `ReminderChange`。`Item.dueDateOnly` / `Reminder.dueDateOnly`（JSON `due_date_only`，只在 true 时出现）；`DueParser.parseDue` 认 `2026-10-20`；`Item.isOverdue` 让只有日期的到期在那天结束前不算逾期。schema v6：`items.due_date_only`、`daemon_state`（`todos_as_of`）。
  - `Patch.status`：任务和 notice 可以改状态；request 不行（用 respond / done / rm）。todo 改成 waiting、改成 notice 都拒绝。
  - inbox：`ingestInbox` 只在有 bridge 时跑，在后台线程一行一行走 `perform`，成功一行就 `Inbox.removing` 删一行（原地重写），失败就停；忙的时候文件又变了就做完再看一次（自己删行触发的变化最多多跑一轮，不会空转）。bridge 报名时也跑一次。
  - stale：`list` 在没有 bridge 且结果里有缓存的 todo 时带 `todos_as_of`（`Service.todosAsOf`：最后一份快照或 bridge 断开的时刻，存在 `daemon_state`；旧库退回缓存里最新的 `updated_at`）。`todo.md` 在没有 bridge 时 "To do" 下面加 As of 行，bridge 来去都重写。
- 测试（#52）：`TodoWritesTests`（真 perchd + 真 `QueueModel` bridge + `FakeRemindersStore` + 真 `perch`，CLI 用 `Task.detached` 跑，不然会堵住主线程上的 bridge）：CLI 增删改、没有 bridge、晚到的 ack（`FakeRemindersStore.readDelay` 推迟读 = 推迟 ack）、字段、promote、7 天、inbox（含没写完的行、bridge 做不了）、stale 输出。`RemindersBridgeTests.oneBridgeAtATimeAndTheNextTakesOver` 改成第二个 App 的写经 bridge 生效。原来 `.disabled` 的五个 inbox 测试搬进 `TodoWritesTests`。纯函数：`DueParserTests.dateOnly`、`MirrorTests.staleTodosSayAsOf`、`InboxTests.removingAnAbsorbedLine`、`StartupTests.migratingToV6…`、`UpdateTests.statusMovesTasksAndNotices`。
- 评审后补的（#52）：bridge 的 ack / 快照走单独的串行队列（`bridgeActions`），不会排在本 App 自己那条正被 perchd 转回来的写后面；做了但读不到列表时 ack 同时带外部标识符和 error，perchd 记下 key 并立刻报错，不干等；超时的写最多再等 30 秒的晚到 ack（`Daemon.lateAckWindow`）；同 `--key` 只在引用表里找到（缓存里没有）时发 `upsert`（还在列表里就改，不在就新建，`RemindersStore.containsReminder`）；inbox 的行晚到的 ack 也会删掉那一行，在途的行不会重发（`inboxInFlight`），每份快照之后再看一次 inbox（列表重建后不用碰文件）。
- **#53 日期、✎、大编辑器**：
  - spike（2026-10-16，macOS 15.6.1，本机 Reminders 不在 iCloud；结果在 #50 的评论）：`open "x-apple-reminderkit://REMCDReminder/<UUID>"` 能把 Reminders 切到那条提醒所在的列表（不打开详情、不明显选中）；`x-apple-reminder://` 没有 App 处理；`REMCDList/<id>` 不切列表，不能当兜底。Reminders 首次的 "启用 iCloud 同步？" 表单挂着时链接无效。用 AppleScript 只设 `due date`（带时间）时 Reminders 自己同时设了 `remind me date`，带 alarm 的到点有通知；所以 Perch 设时间时也加 alarm。做 spike 时建的 "Perch Spike" 列表已删。
  - 日期：`TodoList.dueLabel(item, now:calendar:)`；行用 `queue.now`（每分钟 tick）。只有日期的到期在那天结束前不算过期（`Item.isOverdue`，#52 加的）。
  - ✎：`RemindersStore.localIdentifier(of:inList:)`（EventKit 的 `calendarItemIdentifier`）→ `RemindersBridge.link(for:)` → `QueueModel.openInReminders` → App 注入的 `openReminder`（`Jumper.openReminder`，打不开就只打开 Reminders）+ `NotchModel.close()`。
  - 编辑器：`TodoEditor` 加 `notes` / `hasDate` / `hasTime` / `date` / `url`、`setHasDate` / `setHasTime`（Reminders 的默认：今天、下一个整点、别的日子 09:00）、`edited(item)`；`isLarge` 决定弹窗大小（编辑 440×318）。保存只发改了的：bridge 直接 `RemindersBridge.update(item, ReminderChange(from:to:))`，别的 App 发 `Request.Patch(from:to:)`（patch 新增 `notes` / `link` / `clear_link`）。`TodoPopupPanel.onReturn` 在大编辑器里让 Return 从任何一栏保存（Shift / Option-Return 在备注里换行），Tab 只在添加弹窗里换优先级。
  - 备注：`Reminder.notes` → 缓存的 `meta.notes`（`Item.notes`），不加列。
  - alarm：`ReminderChange.alarms(existing, oldDue:, oldDueDateOnly:)` 是纯规则，EventKit 实现和假 Reminders 都用它；只动绝对时间的 alarm，只动在旧到期时间上的那个。
- 测试（#53）：`DueLabelTests`、`TodoEditorTests`（大编辑器部分）、`ReminderChangeTests`（diff、alarm）是纯函数；`TodoDetailsTests`（真 perchd + bridge + 假 Reminders）：编辑器存所有字段且不动别的（旗标、自定义 alarm、列表、创建时间）、Esc、不是 bridge 的 App 编辑、✎ 的链接和兜底、CLI 的时间带 alarm。`FakeRemindersStore.Entry` 加了 `alarms`，`notes` 挪进 `Reminder`。`TodoWritesTests.unfinishedInboxLinesWaitForTheRest` 在主线程很忙、检查晚于 settle 时间时跳过"还没吸收"那一段（以前偶尔失败）。
- 没做（要人）：本机没有给开发版 App Reminders 权限，Todo tab 只显示 Connect，行和大编辑器都没截图；悬停、点击、日期选择器、Return / Esc / Tab、✎ 的跳转、刘海里设的时间到点提醒，都要在有权限的真 Mac 上人工验；iCloud 列表上外部标识符和本机标识符不同时 ✎ 能不能找到也要验。
- 已知限制（#52）：perchd 推 `todo_op` 时 bridge 的 App 若刚好卡住，CLI 2 秒后报错，但写可能之后才生效（报错信息里说了）。2 秒包括 bridge 写完之后读一遍列表的时间（ack 跟着那次读走），EventKit 读得慢时成功的写也可能报超时。没有 bridge 时 `ls --status done` 里可能有超过 7 天的（缓存不知道完成时间，等 bridge 回来的快照才清掉）。`ls` 的 as of 只看这次列出的东西里有没有 todo。`--due` 带时间时只设到期日期组件，不加提醒（alarm）：#53 起同时加那个时间的 alarm，见下。

## 收起态右翼的 todo 数（#56，2026-10-16）

PR #57 squash 合并为 `0c267b8`，#56 已关；合并前从分支装到了本机（`scripts/install.sh`）。用户想在收起态看到 todo 数，grill 后定的规格在 #56（推翻"收起态只管 agent"，只开一个口子：右翼静态的图标 + 未完成数，从不提醒）。行为见 `docs/PRD.md` 的"收起态"，这里只记实现。

- 数：`QueueModel.collapsedTodoCount` = `todos.openCount`（和 tab 栏同一个数，完成中的 3 秒内还算），没有 Reminders 权限 / 列表（`showsTodos` 为 false）或 perchd 离线时是 0。
- 宽度：`NotchGeometry.collapsedWing(runningCount:online:todoCount:)` 取左右内容里宽的那边，两翼一样宽。量出来 12pt semibold 的 `checklist` 宽 16pt（小怪物 15pt），所以只有小怪物和图标时每翼 27pt（原来 26），一位 todo 数 38，两位 46。
- 画：`CollapsedBar` 右翼有横幅画横幅，否则画 `CollapsedTodos`（有数 `white 0.9`，0 只有图标 `white 0.4`），两者都是 0.2 秒淡入淡出。横幅的宽度和计时没动。
- 测试：`NotchGeometryTests.collapsedWingsFitTheWiderSide`（纯函数）；`TodoModelTests.theFoldedNotchCountsOpenTodos` / `theFoldedNotchCountsNothingWhilePerchdIsAway`（真 perchd + 假 Reminders）。
- 截图（隔离 perchd + debug App；本机开发版没有 "Perch Dev" 列表，截图时本地临时用环境变量写死数，没提交）：0 条暗图标、5 条、Running 1 + todo 12（两翼按右边算）、横幅盖掉 todo、横幅收起后 todo 回来，都对。没刘海的胶囊没截（要外接屏）。

## 小怪物活起来 #58（2026-10-16）

设计在 #58，拆成 #59–#64 六步，从小到大做（Done 带横幅飞那步最后）。所有步骤的规矩：状态的颜色和眼睛（信号）从不变弱、不加新声音、"减少动态效果"全关、todo 从不影响小怪物。

- **#59 Failed / Done 的彩蛋**：`Mood.hasQuirks` 换成每个心情自己的一套 `Mood.quirks`（Idle / asleep 还是哈欠、张望、鼻涕泡，顺序不变所以时间表和以前一模一样，`idleQuirksAreUnchanged` 钉住了 main 的值；Failed 是 `sigh` / `rubHead`，Done 是 `sway` / `hum`）。`nextQuirk(after:in:)` 时间点和心情无关，只按心情的那套抽种类；`Mascot.quirks(_:online:reduceMotion:)` 是 `MascotView` 里 quirk task 的 id（同一套就不重启，所以 idle ↔ asleep 不打断，failed ↔ done 重新排），`Mascot.fps(_:reacting:quirking:)` 管重绘（Failed / Done 平时 0）。Done 的眨眼是 ^ 压扁一点（`Eye.happyBlink`），没有白色，测试按"笑眼或压扁的笑眼"检查；哼歌的 ♪ 和 Idle 的 z 一样飘到右边（Done 是信号时没有 Running，所以盖不到运行数）。
- **#60–#64**（2026-10-19，一个 PR，建在 #59 的 PR #65 上）：
  - #60 汗：`Mascot.frame(_:time:since:…)` 多一个 `since`（`Panel.signalSince`：Running 最早那一轮的 `turnStartedAt`，Needs you 等得最久的 `statusAt`）。≥ 600 s 头边两个白格，每 6 秒（2–3 s 处）右手擦额头。
  - #61 Needs you：60 s 起双手一起挥、每 4 秒跳、天线 0.25 s 闪；300 s 起每 8 秒（从 300 s 起算）敲玻璃 1.75 s（`Eye.wide`、沉 1pt、`Arms.knock`、手边白格）。帧率没动（4 fps；0.25 s 的节奏和原来的轮流挥手一样）。测试用 8 s 的整数倍比 5 / 30 / 120 分钟。
  - #62 鞠躬 / 挠头：`AnswerReactions`（纯，5 秒窗口）+ `QueueModel.answerReaction`（计时器到时清掉，脉冲清掉，展开清掉）。Failed 时保留 X 眼（PR 里注明的选择）。
  - #63 看指针：先用探针 App 验证全局 `.mouseMoved` 不要辅助功能权限（记在 #58）。`Gaze`（纯，45° 五个方向，250pt，别的屏 = nil）、`GazeTracker`（可注入 `PointerMonitor`，只在方向变时发布，Reduce Motion 不装监听），App 侧 `AppKitPointerMonitor` + `panel.acceptsMouseMovedEvents`。`Eye.looking(_:)` / `.peeking(_:)`。
  - #64 Done 飞：`DoneRun`（腿 `Leg` 的分段线性路线，打断时 `cut` 不改原来的参数化，所以打断前的位置一字不差），`DoneRun.flies`（Done 横幅、没有 waiting / failed、没 Reduce Motion），`QueueModel.flight` / `carriesBanner` / `notchWidth` / `reduceMotion`；横幅计时到 `bannerEnd`（卷完）为止，飞行计时到 `end`。`FlightView` / `FlightReveal` 在 `MascotView.swift`。遮罩放在 BannerView 自己身上，横幅淡出时也保持卷起（截图里发现的：放在右翼上时横幅淡出那 0.2 s 会整条重新露出来）。
  - 截图（隔离 perchd + debug App 跑在内建刘海屏上，`-Display automatic -Chimes NO -QuickEntryHotKey …` 只走参数域，不写用户的 defaults）：跳、钻进刘海、拉帘子、站着撒彩纸、卷回去、回到左翼都对。看指针没法截（不能合成鼠标事件），留在 PR 的人工检查清单里。

## 更多 Reminders 列表（M14，#66 / #69 / #70 / #71，2026-10-19）

**状态**：2026-10-19 维护者在真 Mac 上验收通过（验收中修了两处：Lists… 窗口按 Esc 关不掉——从右键菜单里直接 `makeKey`，菜单收起时 key 被还给原来的 App，改成下一轮再开，`ef6fda6`；Doing 的行太不显眼——加整行浅底、标题加粗、▶ 11pt，`750dac8`）。PR #72 squash 合并为 `4e4131c`，分支 `multi-list-reminders` 留在远端。下次发版的 release notes 要写：`perch ls` / `todo.md` 按列表分组、open todo 只按优先级再创建时间排（过期 / 今天到期的不再往前）；schema v7（回退到 v0.4.2 的 perchd 打不开）。

设计在 #66（父 issue），拆成 #69 → #70 → #71。#69 只做数据通路、列表选择和按列表分组；Lists… 窗口、添加弹窗 / 编辑器的列表选择器、`--list` 是 #70（见本节最后）；优先级胶囊、Doing 是 #71。行为见 `docs/PRD.md` 的"Todo tab"和 Reminders 一节，这里只记实现和坑。

- **列表选择**：`PerchAppCore/Reminders.swift` 的 `ListSelection`（注入 `UserDefaults`），`RemindersBridge.selection` / `checkedLists`。defaults 的键按 "Perch" 列表名分命名空间，值都是 `calendarIdentifier` 的字符串数组：
  - `RemindersOrder.Perch`：所有已知列表的顺序；`RemindersChecked.Perch`：勾选的（顺序无所谓）。隔离运行是 `RemindersOrder.Perch Dev` / `RemindersChecked.Perch Dev`。
  - `resolve(lists:perch:)` 在每次 `refresh()`（有权限时）跑：把新的追加到最后（不勾）、加上 "Perch"，只在变了时写回；**从不删**，返回时只过滤掉眼下不存在的（`ListSelectionTests.aMissingListIsLeftOutButNotForgotten` / `noListsAtAllLeaveTheSelectionAlone`、`TodoListsTests.aListMissingForAMomentComesBackCheckedInItsPlace`）。
  - #70 之前手动改：先在 App 跑过一次（顺序里就有所有列表的 id），`defaults read dev.perch.app 'RemindersOrder.Perch'` 看 id（列表名要自己对，EventKit 的 id 没有名字；也可以 `perch ls --json` 看 `todo_lists`，但那里只有勾选的），然后 `defaults write dev.perch.app 'RemindersChecked.Perch' -array <PerchID> <WorkID>`、`defaults write dev.perch.app 'RemindersOrder.Perch' -array <WorkID> <PerchID> …`，展开一次面板（`QueueModel.expanded` → `remindersChanged(listChanged: false)` 发现勾选变了就发快照）或等 Reminders 有变化。
- **接缝**：`RemindersStore.reminders(inLists:completedSince:)` 一次读多个列表、每条带 `Reminder.list`（EventKit 实现里列表全没了就返回空：空的 calendars 对 EventKit 是"所有列表"）。别的方法还是按单个列表；`RemindersBridge.listOf(_:hint:)` 找提醒在哪个勾选列表里（先 hint = 缓存的 `meta.list_id` / `TodoOperation.seenInList`，再别的勾选列表），找不到就报 "that reminder isn't in a list Perch shows"。新建（`add`、`apply(.create)`）还是 `readyList()` = "Perch"；`upsert` 先在勾选列表里找，没有就在 "Perch" 新建。
- **"Perch" 不在时**：`settle(.createList, lists:)` 仍然算勾选的其他列表，所以快照里还有它们（Todo tab 照样只显示 Create Perch list 按钮）。
- **线上协议**：`ReminderList` 从 PerchAppCore 挪到 PerchCore（Codable：`id` / `title` / `icloud`）。`todo_snapshot` 多 `lists`；`list` 的回答多 `todo_lists`（有才带）；watch 上 `Response(todoLists:)` 推送（`Push.lists` / `QueueConnection.Update.lists`），perchd 在同一份快照的 item 事件**之前**推，连接时 `QueueConnection` 也先发 `.lists` 再发 `.snapshot`。`Item` 编码多一个只出不进的 `list`（= `meta.list_name`）。`TodoOperation.seenInList`（`seen_in_list`）：perchd 上次看到提醒的列表，只是提示；#70 要的"目标列表"（新建、移动）另起字段，不要复用它。
- **perchd**：`Service.applySnapshot(_:lists:)` 把列表描述存在 `daemon_state` 的 `todo_lists`（JSON，不改 schema；没有 `lists` 的快照存空数组 = 旧的不分组模式），每条 todo 的 `meta` 写 `list_id` / `list_name`；列表改名会让 todo 的 `meta` 变，发 updated。`queueOrdered(now:calendar:lists:)`：open task 一个槽，按列表位置（不在列表里的排后面）、优先级、创建时间、id，**到期日期不再排序**（#69 写明"then priority, then age"，`QueueOrderTests.fixedOrder` 跟着改了）。`MirrorRenderer.render(_:lists:todosAsOf:)`：有列表时 "To do" 总是出现，每个列表一个 `###`，空的 "All clear"，这时不写 "Nothing waiting."。分组的共用逻辑是 PerchCore 的 `todoGroups(lists:)` / `Item.todoOrder`。
- **App**：`QueueModel.todoLists`（perchd 推来的，所以不是 bridge 的 App 和没有 Reminders 的 App 也一样分组）；`todos` = `TodoList(items:lists:unlisted:)`。`TodoList` 丢掉不在勾选列表里的 todo（列表先到、item 事件后到，所以那是刚取消勾选的）；一个列表都没有（#69 之前的缓存）时所有 todo 一组，叫 `remindersListName`。`RemindersState.note` 删了，换成 `TodoList.Group.notSyncing`。`PanelLayout.todoHeight` 给空组算一行 "All clear"。
- **CLI**：`perch ls` 的人类输出在每组 open todo 前打一行 `[列表名]`（按 `listID` 换组）；只在 todo 带列表时打，所以只有旧缓存（或测试里不带 `lists` 的假 bridge）时和以前一样。
- **测试**：`TodoListsTests`（真 perchd + `QueueModel` bridge + 假 Reminders：分组和顺序、计数、Todo tab 写到自己的列表、添加进 Perch、取消 / 重新勾选短 id 不变、挪到没勾的列表、删掉勾选列表、改名 / 不在 iCloud、"Perch" 没了、perchd 重启后列表还在且普通 App 也分组）、`TodoListsCLITests`（真 `perch`：`ls` / `--json` / `todo.md` 分组、没有 bridge 照样、CLI 写任何勾选列表、`perch add` 和 inbox 进 Perch）、`ListSelectionTests`（注入 defaults）、`TodoListTests`（纯函数）、`ServiceTests.snapshotsCarryTheirLists`、`MirrorTests.toDoHasASubheadingPerList`、`QueueOrderTests.openTasksGoByListFirst`、`ModelsTests.aTodoCarriesItsListOnTheWire`。`FakeRemindersStore` 加了 `phoneMove` / `phoneCreateList` / `setICloud` / `lastRead`。坑：测试里 `TestDaemon()` 一定要先存进变量，直接写在参数里会在调用后释放、server 停掉，现象是快照永远到不了。
- **发版说明要写**：`perch ls` 现在按列表分组，每组前一行 `[列表名]`（只靠 stdout 行数解析的脚本会受影响，`--json` 不变，只多 `list` / `todo_lists`）；open 的 todo 严格按优先级、再按创建时间排，过期 / 今天到期的不再往前浮（`todo.md` 的 "To do" 也一样）。
- 提交：`db18c32`（perchd / CLI / todo.md）、`2aaa364`（bridge、选择、Todo tab）、`f190535`（文档）；评审后：`274bb0c`（选择从不删列表）、`0bd9d90`（`TodoOperation.list` 改名 `seenInList` / `seen_in_list`）、整理（列表名兜底、位置索引、`locate`），再加这次的文档。
- **没做（要人）**：真 Mac 上的人工验收（本机开发版没有 Reminders 权限，没截图）：用 `defaults write` 勾上别的列表后展开面板，看分组、"All clear"、"Not syncing"、组标题样式；在别的列表里完成 / Undo / 编辑 / 改优先级 / 删除 / ✎；取消勾选再勾上短 id 不变。`CONFIG=debug scripts/bundle-app.sh` 能编过。
- **已知限制 / 风险**：
  - 选择从不删 id：真删掉的列表的 id 一直留在 `RemindersOrder` / `RemindersChecked` 里（只是不显示），换来的是 EventKit 一时少列几个列表（iCloud 抖一下、启动时账户没加载完、`createList` 状态）时勾选和位置不丢（评审后改的）。
  - `defaults write` 改选择要等下次展开面板或 Reminders 有变化才生效（App 不监听外部 defaults 改动）。
  - 跨账户挪提醒（iCloud → 本机）时 EventKit 可能换外部标识符，那时短 id 会变：#66 的 Further Notes 说留给 #70（移动列表）去核实。
  - 两个勾选列表同名时 `perch ls` 的组标题一样（按 id 分组，不会混）。

**#70（Lists… 窗口、`--list`、列表选择器）**，同一个分支、同一个 PR #72：
- **EventKit spike**（2026-10-19，macOS 15.6.1，这台 Mac 只有 iCloud 账户、没有"本机"）：在 "Perch Dev" 建一条提醒，改 `calendar` 到同账户的临时列表 "Perch Dev Probe" 再 `save`：`calendarItemExternalIdentifier` 和 `calendarItemIdentifier` 都不变，新的 `EKEventStore` 按旧的外部标识符在新列表里找得到；探针的提醒和列表都删了。跨账户没法验证，所以拒绝跨账户挪（下面）。结果记在 #70 的评论里。
- **线上协议**：`Request.list`（`add` 的目标列表名）、`Request.Patch.list`（`update` 挪去的列表名）——都是给人和 agent 的名字；perchd 解析成 id 后放进 `ReminderChange.list`（`todo_op` 的 `change.list`，新字段）：新建进那里、改的时候挪过去。`TodoOperation.seenInList` 照旧只是查找提示。`ReminderList` 多 `account`（EventKit 的 `source.sourceIdentifier`，`todo_lists` 里也带，旧 bridge 没有就不查）、改成 Hashable。
- **名字解析** `ReminderList.checked(named:in:)`（PerchCore，perchd 和 bridge 共用错误文案）：精确匹配；0 个是 "no checked Reminders list is called 'X' (names match exactly); checked lists: …"，多个是 "N checked Reminders lists are called 'X' (rename one in Reminders); checked lists: …"；没有列表时写 "none yet (is Perch.app running?)"。perchd 只知道勾选的列表，所以"没勾"和"不存在"是同一个错误。`Service.planAdd` / `planUpdate` 在做任何事之前解析，但先看是不是 todo：`--list` 给了非 todo（等待中的、notice、request）不管名字对不对都是 "a list only applies to todos (open or done tasks)"（`add` / `update` 的本地路径也查；`--wait` 在 CLI 里就拒绝，因为它不经过 `add` 的 `list`）。回答写的人时（`todoWriteAnswer`）再看快照里的 todo 是不是真在 `change.list` 里：不在就报错（"… not the list asked for: Perch.app is older than perch; update it"）——#70 以前的 Perch.app 不认识这个字段，会建进 "Perch" / 不挪，不能让 agent 以为成功了。`planChange(_:to:list:)`：目标就是现在的列表时不发 list（可能整个改动为空，直接回答）；跨账户 → `moveRefusal`。
- **bridge**：`RemindersBridge.checkedList(_:)` 按自己当时的 `checkedLists` 再查（"that Reminders list isn't checked in Perch; checked lists: …"），`moving(_:from:)` 去掉指向原列表的 list、跨账户拒绝；`add(title:priority:list:)`、`apply(.create)` 有 `change.list` 就建在那里，没有就 `readyList()`（"Perch"）。`RemindersStore.updateReminder` 的约定：`change.list` 是别的列表就挪（EventKit 改 `reminder.calendar`，假 Reminders 改 `Entry.list`）；`createReminder` 不看 `fields.list`。
- **选择**：`ListSelection.reorder(_:)`（窗口里显示的那些 id 按新顺序填回它们原来占的位置，一时不在的列表不动，不认识的放最后）、`ordered(_:)`（窗口的行）；`RemindersBridge.allLists` / `choices`（`ListChoice`：列表、勾没勾、"Perch" 锁死）。`QueueModel.listChoices`（@Published，每次 `remindersChanged` 更新）、`choosesLists`（有权限：ready 或 createList）、`setListChecked` / `reorderLists` / `refreshLists`；改选择后走 `remindersChanged(listChanged: false)`，勾选列表（含顺序）变了就发快照。`reorderLists` 收的是 id 数组，因为 `Array.move(fromOffsets:toOffset:)` 在 SwiftUI 里，PerchAppCore 不引 SwiftUI。
- **弹窗**：`TodoEditor.list`（`ReminderList?`；添加时 nil = "Perch"，`openAdd` 每次新建 editor 所以总回到 "Perch"，提交后下一条沿用选的列表；编辑时 `edit(_:lists:)` 找 todo 自己的列表，找不到就是 nil、保存不挪）。`edited` 换了列表才写 `meta.list_id` / `list_name`，`ReminderChange(from:to:)` 出 `list`（id）、`Patch(from:to:)` 出 `list`（名字）。`QueueModel.perchList`、`editorLists`（添加：所有勾选列表；编辑：同账户的）。提交添加时选的是 "Perch" 就不带 list，和 CLI 一样。`QueueModel.editorList` 是选择器显示的、也是添加真正去的列表：editor 选的 → "Perch" → （添加时 "Perch" 没了）第一个勾选列表，所以显示什么就进哪里。
- **App**：`PerchApp/ListsWindow.swift`（`ListsWindowController` 复用 `TodoPopupPanel`：不激活、Esc / 失去 key 就关；位置和弹窗一样，收起时在刘海下面、展开时在面板下面；高度随列表数，最多 12 行再滚动）；SwiftUI `List` + `.onMove` 拖动，勾选框 `.toggleStyle(.checkbox)`，"Perch" 的 `.disabled`。右键菜单最上面的 "Lists…"（`NotchMenu.lists`，`queue.choosesLists` 时才有）。`TodoPopup.swift` 的 `ListPicker`（`.menu` 样式的 Picker）：添加弹窗在标题栏右边（只在 `editorLists` 不止一个时），大编辑器在 URL 上面一行（编辑器高 318 → 348）。
- **测试**：`TodoListPickTests.swift`：`TodoListFlagTests`（真 `perch`：`add --list` / 默认 / inbox、`update --list` 挪且短 id 和别的字段不变、四种坏名字 × add / update × 人类 / `--json` 且什么都不写、非 todo 拒绝、bridge 再查、跨账户拒绝和编辑器只列同账户）、`ListPickerTests`（`QueueModel`：Lists… 的行、勾选 / 拖动立刻改分组 / `list` / `todo.md`、"Perch" 不能取消、新列表 / 删列表、没权限没有窗口、添加弹窗、编辑器挪且不动别的、普通 App 经 perchd 加和挪）；`ListSelectionTests` 加了拖动和勾选的持久化；`TodoEditorTests.theListPickerMovesOnlyWhenChanged`；`ListNameTests`（ModelsTests.swift）。`FakeRemindersStore` 的列表都带账户（`iCloud` / `onMyMac`，`phoneCreateList(_, iCloud: false)` 是本机），`updateReminder` 能挪。
- **没做（要人）**：Lists… 窗口、拖动、两个选择器的样子和手感都没截图、没点过（本机不能合成鼠标事件，打开窗口要右键）：要在真 Mac 上验：窗口打开时终端还是前台、拖动 "Perch"、锁死的勾选框、Picker 的菜单在不激活的面板里能弹出且选完标题栏还有焦点、编辑器的 List 行。跨账户的真实行为（有"本机"账户的 Mac 上 EventKit 挪提醒会不会换外部标识符）没验证，现在是拒绝。
- **评审后改的**：上面的错误顺序、`--wait`、旧 bridge 的检查和 `editorList`；`NotchWindowController.popupFrame(size:belowPanel:gap:)` 给弹窗和 Lists… 窗口共用位置（没有位置时 Lists… 不显示）；`ReminderList` 退回 Equatable。`TodoEditorModelTests.aTodoAddedWhileThePanelIsOpenHighlightsBriefly` 的高亮时间从 0.3 秒放宽到 2 秒：新的 CLI 测试并行起很多 `perch` 进程，整套测试时主线程慢，0.3 秒会在两次检查之间过期（单独跑总是过）。
- **已知限制（#70）**：不是 bridge 的 App 的选择器按列表名经 perchd 写，所以两个勾选列表同名时它选哪个都报"重名"（bridge App 按 id 写，不受影响）。不是 bridge 的 App（同时开了两个 Perch.app）在 Lists… 里改的选择写进同一个 defaults，但 bridge 要等下次 Reminders 变化或展开面板才发快照。弹窗的列表选择器列的是 perchd 推来的 `todo_lists`，所以刚勾上的列表要等那份快照到了才出现。

**#71（优先级胶囊、Doing）**，同一个分支、同一个 PR #72：
- **存储**：schema v7 是 `ALTER TABLE todo_refs ADD COLUMN doing INTEGER NOT NULL DEFAULT 0`。`Store.select` 用相关子查询 `COALESCE((SELECT doing FROM todo_refs WHERE todo_refs.id = items.id), 0)` 把它读进 `Item.doing`（第 17 列），所以 `get` / `list` / 事件里都有；`Store.update(item)` 不写它，只有 `Store.setDoing(_:forRef:)` 写。`TodoRef.doing`。
- **线上**：`Item.doing` 在 JSON 里对每条 todo（有 `meta.reminder`）都出现（true / false），别的 item 没有；解码时缺省 false。`Request.Patch.doing`。`add` 的 `normalized` 把它清成 false（HTTP 客户端塞进来也没用）。
- **perchd**：`planUpdate` 看到 patch 有 `doing` 就返回 `.local`（不经 bridge），`Service.update` 再交给 `setDoing`：patch 里还有别的字段 → "doing (--doing / --no-doing) goes on its own …"；不是 todo（`todo_refs` 里没有）→ "… Doing only applies to todos (open tasks in Reminders)"；不是 open → "… isn't open (it's done); only open todos can be Doing"；值没变 → 成功、不发事件；否则只写引用、重新读出 item 发 updated（缓存的 item 行不动、`updated_at` 不变：缓存只由快照写）。`applySnapshot`：每条提醒的 `item.doing = ref.doing && !completed`，完成的同时清引用；缓存里有、快照里没有的 todo，Doing 为真且（快照根本没带 `lists` = #69 以前的 bridge，或它的 `list_id` 在快照的勾选列表里）就清引用，否则留着（列表取消勾选了；`lists` 是空数组 = EventKit 一时什么都没列出来、或 "Perch" 没了又没勾别的，什么都证明不了）。所以 `applySnapshot(_:lists:)` 的 `lists` 是可选的，`Daemon` 原样传 `request.lists`（评审后改的：原来空数组也清，一次空快照就丢掉所有 Doing）。
- **排序和标记**：`Item.todoOrder` 先比 Doing，所以 `todoGroups`（Todo tab、`todo.md`）和 `queueOrdered`（`perch ls`）一起变。`Format.row` 在标题后面加 `  · doing`（在优先级标记之前）；`MirrorRenderer.line` 的详情第一项是 `doing`（在 `request` 之后，todo 不会是 request）。标记用小写，和 "high priority" 一致。
- **App**：`QueueModel.toggleDoing(_:)` 发 `update` + `Patch(doing: !item.doing)`，bridge 和普通 App 一样经 perchd。`TodoViews.swift`：▶ 是 `play` / `play.fill`（9.5pt，Doing 时 11pt）；Doing 的行有 8% 白的圆角浅底（刚加的 1 秒高亮 14% 优先）、标题 semibold，不显示时 `.opacity(0)` + 不接点击但占位（悬停时日期不跳）；完成中（Undo）不显示 ▶。`PriorityCapsule`：10pt semibold，水平 6pt、高 15pt，High / Low 字 95%、底 20%，Normal 字 50%、底 10% 白；颜色复用 `SessionStatus.color(.waiting)` / `.running`。悬停用 `HoverTracker`（`NSViewRepresentable`，`.activeAlways` + `.inVisibleRect` 的 tracking area，`hitTest` 返回 nil），因为 SwiftUI 的 `.onHover` 在不是 key 的面板里靠不住（`NotchHostingView` 也是这么做的）。
- **测试**：`TodoDoingTests`（`QueueModel` 的 ▶、Doing 在列表最前且可以多条、计数和摘要不变、Reminders 不动；手机上完成 / tab 里完成后清掉、重新打开不回来；挪到没勾的列表再挪回来是普通的、删掉后引用不再是 Doing；手机上挪 / 编辑器挪到别的勾选列表、取消再勾选都还在）、`TodoDoingCLITests`（真 `perch`：有 bridge 和没 bridge 都能设、`ls` / `--json` / `todo.md` 的顺序和标记、`--no-doing`、重复设、做完的 / 等待中的 task / 和别的字段一起 都拒绝）、`TodoListTests.doingFirstThenPriorityThenAgeThenIdInEachList`、`StartupTests.migratingToV7AddsDoingToTodoReferences`、`ModelsTests.aTodoCarriesDoingOnTheWire`、`ServiceTests.doingClearsOnlyForATodoGoneFromACheckedList`（空快照留着、旧 bridge 的快照清掉）。`UpdateTests` / `UpdateCLITests` 的"至少给一个"文案多了 doing。
- **评审后改的**：上面的空快照；`setDoing` 不再写缓存的 item 行；`HoverTracker` 在每次设 tracking area 时看一眼指针在不在里面（行出现在指针下面、Doing 后挪了位置时没有 entered 事件）；`perch update` 的"至少给一个"改用 `Patch.isEmpty`。
- **没做（要人）**：胶囊的颜色、▶ 的悬停（尤其是刘海面板不是 key 时 `HoverTracker` 收不收得到）、点 ▶ 的手感都没截图、没点过（本机开发版没有 Reminders 权限，不能合成鼠标事件）。
- **已知限制**：Doing 只在这台 Mac 的 perchd 里，`~/.perch` 的数据库丢了就没了（和短 id 一样）；两台 Mac 各有各的。`perch update --doing` 不能和别的字段一起给（要两次）。

## M15 进度：dsh（DeepSeek Harness，#73，2026-10-19）

**状态**：✅ 完成。2026-10-19 真模型验收通过（维护者本机，Claude 按维护者要求跑的），PR #79 squash 合并为 `5a2ed8b`，#73 和三个子 issue 都已关。还没发版（下一个版本带上）。

v0.5 接更多 agent（#24）的第二个。dsh 是 DeepSeek 的 Node agent 框架，profile 由 cordis 插件一层层叠出来；只能从里面扩展，所以 Perch 带一个只搬运事件的 JS 插件（CLAUDE.md 规则 7 的唯一例外，#73 定），状态全在 Swift 里判。

- **探针**（#73）：`dsh <profile> --patch overlay.yml` 挂一个只记录的插件（插件名可以是绝对路径），`DEEPSEEK_BASE_URL` 指向本地脚本化的假模型（Anthropic Messages + SSE；关键词选场景：要审批的 bash、ask_user、400、慢速流），所以每种情形都能稳定复现、不花额度。探针和假模型的源码在 #75 里。引导页的连通性检查不走 base URL，按 Esc 跳过。临时 `DSH_HOME`（把 profile 链接进去）完全隔离，不碰真的 `~/.dsh`。
- **#74 / #75**：分两个 session 并行做，PR #77 / #78 squash 合并（`36d20d3` / `e68848f`）。合并前把两个分支合在一起跑了一遍端到端：隔离的 perchd（`PERCH_HOME`、`--no-http`）+ dsh-tui + 假模型，每种情形的会话状态都对；关终端 25 秒内靠 pid 存活检测清掉。
- **#76 安装**：home patch 层 `$DSH_HOME/cordis.patch.yml` 对所有 profile 生效（实测：`--dump-config` 里有那一行、注释保留、绝对路径变成 `file://`）；`name` 指向不存在的文件时 dsh 照样启动（实测），所以插件没了不会弄坏 dsh。插件不再从 App bundle 拷（CLI 在 `~/.perch/bin` 或 `.build/debug` 时旁边没有它），而是嵌进 PerchSetup（`scripts/dsh/embed-plugin.sh` 生成 `DshPluginSource.swift`，测试保证和 `packaging/dsh/perch.mjs` 一字不差），作为 hook 的附带文件写在 perch 旁边；#78 加的 bundle 拷贝去掉了。
- **真模型验收**（2026-10-19，维护者本机，dsh 0.2.1-rc.2 + dsh-tui 0.16.1）：在 Ghostty 里用 AppleScript 驱动（`new window` + `initial input` 起 dsh-tui，`input text` / `send key` 打字；方向键要用 `perform action "text:\\x1b[B"`，`send key` 不认 `down` / `arrow_down` / `ArrowDown`）。API key 在维护者登录 shell 的环境里，Claude 的工具 shell 读不到，所以真模型只能在 Ghostty 里跑；`~/.dsh/.credentials.yaml` 里只有 `dsh web` 的浏览器会话。逐项结果在 MILESTONES 的 M15。修了两处：dsh 的 cwd 是 realpath，Ghostty 是 `/tmp/…`，聚焦的 terminal 对不上，链接没有 id（`TerminalLink.sameTree` 解析符号链接）；dsh-tui 0.16.1 让模型每条回复先写 `⏵` 旁白，Done 那行显示的是旁白（`HookAdapter.dshReply` 跳过）。关窗口后约 56 秒才清掉（tmux 里 25 秒），原因没查清。dsh-tui 0.14.0 不认 dsh 0.2.1-rc.2（profile 里的 dsh-tui 要单独升：`dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui@0.16.1`）。
- 坑：dsh 会把上一轮没回答的 prompt 和下一条拼在一起发给模型（失败的一轮之后），假模型要只看最后一行；dsh-tui 的启动器（`dsh-tui` / `dst`）最后总是 spawn `dsh --profile dsh-tui`，所以跑插件的进程永远是 `node …/bin/dsh`。

## M16 进度：dsh web 的会话上刘海（#80，2026-10-20）

起因：维护者在 dsh web 里发消息，刘海没反应——#73 定了只支持终端 UI，插件看到 `webStartup` 就不动。一开始以为是 dsh web 本身坏了：19 号 17:18 起的那个 dsh web 确实卡住了（HTTP 正常、不吃 CPU，但不回消息），重开就好了，和 Perch 无关（隔离实例有没有 Perch 那一行、运行中加 / 删那一行都正常回复）；维护者重开后还是"不行"，看 dsh 的投影缓存（只看状态字段）才确认 web 会话每轮都回复了，"不行"指的是刘海不显示。

- **设计**（#80）：一个 web 会话一行，第一条 prompt 才出现；链接是 dsh web 对外的根地址（不带 token），点了在默认浏览器打开（没有单个会话的地址，每次开新标签页）；Needs you 写 "Answer in dsh web"；服务停了全部移除，Idle 满 30 分钟的浏览器会话移除（perchd `reap`，按链接是 http(s) 判断，不改 schema）。
- **实测**（隔离的 `DSH_HOME` 链接 `~/.dsh/profiles/web`，假模型，浏览器面板）：见 MILESTONES 的 M16。坑：浏览器面板里 `find` 返回的 ref 每次都会变，点之前要用这次的；`about:blank` 在浏览器面板里不能用，要"关掉"页面就导航到别的本地地址。
- 测试里 `sameTree` 的符号链接用例原来依赖 `/tmp/perch-dsh-real` 这个目录存在（删了就失败），改成测试自己建目录。

## 未决问题

| 问题 | 影响 | 状态 |
| --- | --- | --- |
| 装不装 Xcode（决定 M2 构建路线） | M2.1 | ✅ 已定：不装，SwiftPM + `scripts/bundle-app.sh` |
| Live Activity（"2 agents · 4m"）的数据从哪来 | M2.3、M3 | ✅ 内存 session，按轮计时（UserPromptSubmit → Stop / StopFailure / SessionEnd） |
| `update` / snooze op 的形状 | M2.5 | ✅ 已定：通用 `update` op + `perch update`（见上方） |
| 全局快捷键默认值（快速录入；⌥⇧A / ⌥⇧D / ⌥⇧O） | M2.6、M4 | ✅ 快速录入 ⌥⇧Space；其余沿用 PRD，M4 实现 |
| `link` 跳回终端的机制（Zed / Warp / tmux / iTerm） | M2.4 跳转按钮、M3 | ✅ Ghostty AppleScript focus terminal id；其他终端激活 App |
| hook 等刘海的超时取 15 秒还是 30 秒 | M4 | ✅ 先用 20 秒（`--wait` 可改），用一周后再看 |
| 开源许可证 | 分发 | ✅ MIT（2026-10-08，#4），`LICENSE` 在仓库根目录 |
| README | 分发 | ✅ 重写（2026-10-08，#5）：英文，按 v0.2 的 agent 面板写；截图在 `docs/images/`，不含真实数据。面板有变化时要重截，步骤见下 |

README 截图怎么重做（`scripts/readme-images/`）：
1. 先退出自己的 Perch（`osascript -e 'quit app id "dev.perch.app"'`），不然两个面板会叠在一起。
2. `PERCH_HOME=/tmp/perch-shot swift run perchd --no-http &`，然后 `python3 scripts/readme-images/seed.py /tmp/perch-shot/perchd.sock` 造示例会话（五种状态，带 Allow / Deny 的 request）。
3. `scripts/bundle-app.sh` 后，用 `PERCH_HOME=/tmp/perch-shot PERCH_PIN_EXPANDED=1` 启动 `.build/Perch.app`，`screencapture -x -o -l <窗口号>` 截面板窗口，得到 `docs/images/panel-expanded.png`（Running 的点在呼吸，多截几张挑亮的）；不带 `PERCH_PIN_EXPANDED` 再截一张收起态。窗口号用 `CGWindowListCopyWindowInfo` 按 pid 找。
4. 合成桌面：`swift scripts/readme-images/compose-desktop.swift <面板截图> docs/images/desktop-expanded.png 520 2400`（收起态用 `100 2400`）。`docs/images/mascot-states.png`（#22）是六种状态的小怪物各截一张收起态、裁出小怪物（@2x 像素 46×46，起点 (14, 10)）、最近邻放大 4 倍、黑底横排拼成的。墙纸是生成的渐变，菜单栏只画 Finder 菜单、电池、Wi‑Fi、控制中心和 9:41，不露真实桌面。
5. 关掉测试用的 perchd 和 App，重新打开自己的 Perch。

## 已知限制 / 技术债

剩余工作都已开成 GitHub issue：https://github.com/cryptowizard0/perch/issues
（#1 M4 验收 · #2 M5 Codex · #3 M6 Hermes · #4 许可证 · #5 README · #6 #7 inbox · #8 Esc 打断 · #9 自启 + 图标 · #10 URL scheme / 其他终端 · #11 展开态高度 · #12 UI 自动化测试 · #13 等待时长复盘）。做完一项就关对应 issue。

- ~~inbox 最后一行没写完就被吸收~~ 已修（#6，2026-10-08）：没有换行符的最后一行先不吸收，文件 1 秒没变（`Daemon.inboxSettle`）才算写完；所以保存时不带结尾换行的编辑器，最后一行会晚 1 秒进库。
- inbox 在"读取 → 核对 → 原地重写"之间有微秒级窗口，这期间追加的行可能丢失（已尽量缩小）。
- 从 `.build/` 执行 `perchd install` 会打印提醒：执行 `swift package clean` 后 agent 就会失效。日常使用要先把二进制复制到固定位置再装。
- 测试用的 Unix socket 放在 `/tmp/perch-test-*`：socket 路径上限 103 字节，`/var/folders/...` 太长。
- CLITests 通过 `--test-bundle-path` 找 `perch` 二进制（swift-testing 跑在 `swiftpm-testing-helper` 里，`Bundle.main` 不可用）。
- Perch.app 还不会开机自启（perchd 有 launchd，App 没有）。2026-10-08 用户定先不做（#9）；候选方案：`install.sh` 加一个登录时 `open -a` 的 LaunchAgent（推荐），或 App 里 `SMAppService.mainApp`（ad-hoc 签名每次重建都变，没实测过）。
- App 图标（2026-10-08，#9；2026-10-10 换形象）：原来是奶白像素小鸟站在刘海上；现在是刘海里那只独眼怪（`Mascot` 的同款精灵图，Needs you 的橙色 `#FF941A`），双手抓着贴在图标顶边的刘海下沿吊着、天线插进刘海里。用户从 5 个方案（站在刘海上 / 吊在刘海下 / 大头像 / 三只一排 / 黑底刘海）里选的。背景仍是 README 截图同款渐变。16px 下手臂会糊，只剩橙色色块 + 白眼，Retina 的 16pt（32px）清楚。`scripts/icon/draw-icon.swift` 画 1024 母版并缩出 16–1024 的 iconset，`scripts/icon/make-icon.sh` 用系统自带的 `iconutil` 打成 `packaging/Perch.icns`（不需要 Xcode / actool），`bundle-app.sh` 拷进 `Contents/Resources`，Info.plist 的 `CFBundleIconFile` = Perch。Perch.app 不进 Dock，图标出现在 Finder、Spotlight、登录项和系统通知里。
- 展开态高度是估算的（request 按 52 字 / 行算），很长的 request 靠列表滚动兜底。
- `link` 只能打开 URL 和绝对 / `~` 路径；tmux 等终端会话引用没有跳转按钮，等 M3 定机制。
- #8（2026-10-08 实测，Claude Code 2.1.258，`claude --settings` 挂一个记录所有事件的 hook）：权限提示上选 No 或按 Esc，**不发任何 hook**（`idle_prompt` 等了 2.5–5 分钟也没来），transcript 里写 `[Request interrupted by user for tool use]` + `turn_duration` → 已修：perchd 监视 Running / Needs you 会话的 transcript，见到标记就转 Idle（`ClaudeTranscript` / `TranscriptWatcher`，schema v3 加 `transcript_path`）。Claude 还在思考、没输出时按 Esc：hook 和 transcript 都没有任何记录（prompt 被放回输入框）→ 没有可靠信号，会话停在 Running 直到下一条 prompt 或关 tab，记为已知限制。输出到一半按 Esc：transcript 写 `[Request interrupted by user]`（不带 "for tool use"），同一个修法能认（2026-10-08 实测变灰）。命令运行中（`sleep 30`）按 Esc 也实测变灰。Codex 有 Interrupt hook，没这个问题。用户实测（2026-10-08，重装后）：权限提示上选 No、按 Esc，刘海那行都在一两秒内从橙变灰。
- 非 Ghostty 终端只能激活 App，定位不到 tab。Perch.app 还没有注册 `perch-terminal://` URL scheme（todo.md 里的这类链接点不开）。
- Grok（M11）：Needs you 不显示命令（`permission_prompt` 没有）；刘海不能批准 Grok；leader 模式下会话要等 leader 退出才清；Grok Bot.app 不显示。
- 点击 / 快捷键的 UI 路径没有自动化测试（只测了 `QueueModel` 的 open / remove / openHead / answerHead），改交互要人工回归上面的清单。

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
