# 里程碑

每一步都能独立验证再往下走；第 3 步完成时产品已经能日常使用。M1–M6 已完成；2026-09-28 方向调整为 agent 面板（见 `PRD.md`"v0.2 方向调整"），当前：**M7**。

## M1 — daemon + CLI + SQLite + watch（不带 UI）

- [x] `perchd` 启动：建 `~/.perch/`，打开 SQLite（建表 `items`），监听 Unix socket 和 `127.0.0.1:7331`
- [x] 实现 `Request.Op` 全部操作：ping / add / list / get / done / respond / remove / watch
- [x] `add --key` 幂等：同 key 再 add 更新原项，不新建
- [x] `watch` 客户端收到 `item.added` / `item.updated` / `item.removed` 事件
- [x] `perch` CLI 全部子命令连上 daemon，`--json` 输出；daemon 未启动时给出清晰错误
- [x] `--due` 支持 `@15:00` 和 `+30m` 两种语法
- [x] request 的 `--wait`：阻塞到 `response` 写入或 `expires_at` 到期
- [x] `~/.perch/todo.md` 只读镜像随每次变更重渲染；`~/.perch/inbox.md` 的 `- [ ] …` 行被吸收并清空
- [x] launchd plist 生成与安装（`perchd install` 或类似）
- [x] 验收：两个终端互相 `add` 和 `watch`，事件延迟肉眼无感；重复 `--key` 不产生重复项；`swift test` 通过

## M2 — 刘海 UI

- [x] `scripts/bundle-app.sh` 打出 `Perch.app`（SwiftPM，无需 Xcode），可运行，无 Dock 图标
- [x] NSPanel 贴在刘海位置；无刘海的 Mac 退化为顶部居中小胶囊
- [x] 收起态：数字、颜色点（灰 / 蓝 / 橙 / 红）、Live Activity（"2 agents · 4m"；数据来源 M3 定，目前为空时隐藏）
- [x] 展开态：固定排序 request → waiting → 逾期 → 今日 → 其余 open → notice；每行来源图标、标题、相对时间、跳转
- [x] 点标题完成；⌥ 点推迟 30 分钟；notice 到 `expires_at` 自动消失，点一下转 task
- [x] 全局快捷键弹快速录入（⌥⇧Space，Carbon `RegisterEventHotKey`，不需要辅助功能权限）
- [x] `due_at` 到时：系统通知 + 刘海脉冲
- [x] 验收：CLI 调用到刘海更新 ≤ 200 ms（`scripts/measure-latency.sh`：release 版均值 11 ms、最差 14 ms）

## M3 — Claude Code 被动接入

- [x] hook 适配器 `perch hook claude-code`（Swift 子命令，不用 shell 脚本）：`UserPromptSubmit` / `Stop` 维护 Live Activity（按轮计时）；`Notification` 生成 waiting；`Stop` resolve 并发 notice
- [x] `perch hooks install claude-code` 写 `~/.claude/settings.json`，`uninstall` 干净移除
- [x] 验收：跑一个需要权限的任务，刘海变橙；跑完后 notice 出现并自动消失（Ghostty 与 Claude 桌面 App 均已实测）

## M4 — PermissionRequest + 白名单

- [x] `PermissionRequest` 适配：白名单内发 request 等刘海（默认 20 秒），超时 / 白名单外不返回决定，改发"去终端"的 waiting
- [x] 白名单配置文件 + 默认值（`~/.perch/allowlist.json`，`perch allowlist`）；白名单外只显示"去终端"
- [x] 展开态 request 行：完整命令原文 + Allow / Deny / 终端；⌥⇧A / ⌥⇧D 处理队首（只在有 request 时注册），⌥⇧O 跳队首
- [x] 验收：刘海里 Allow 一次 `npm test`，终端不弹提示；`rm` 只显示"去终端"；超时后终端提示正常弹出

## M5 — Codex 复用

- [x] 同一套适配器 `perch hook codex`（核对后返回 JSON 与 Claude Code 相同，不用分支；新增 `Interrupt` 结束一轮）；`perch hooks install codex` 写 `~/.codex/hooks.json`，`uninstall` 干净移除
- [x] 验收：同 M3、M4（Codex 没有 Notification：白名单外的命令靠 PermissionRequest 的"去终端"变橙）

## M6 — Hermes 接入

原计划是 Docker 里的 Hermes 走 HTTP；实际 Hermes 跑在本机、有 shell hook，改为 hook 适配（用户定）。HTTP `POST /rpc` 仍在，留给容器客户端。

- [x] `perch hook hermes`：`pre_llm_call` / `post_llm_call` / `on_session_end` 维护 Live Activity 和 notice；`pre_approval_request` 生成"去回答"的 waiting（完整命令），`post_approval_response` resolve
- [x] `perch hooks install hermes` 写 `~/.hermes/config.yaml` 的 `hooks:`（带标记的块），`uninstall` 干净移除；已有自己的 `hooks:` 时拒绝
- [x] 刘海：gateway 的审批显示"Answer in Telegram"等
- [x] 验收：Hermes 一轮 → Live Activity + notice；让它跑 `rm -rf <临时目录>` → 刘海变橙，在 Hermes 里回应后消失

## M7 — 会话状态机（daemon + CLI + hook，不动 UI）

- [x] `sessions` 表（schema v2，`PRAGMA user_version` 迁移）：状态、source、title / cwd、link、prompt、last_message、detail、error、pid / pid_started_at、各时间戳
- [x] 状态机：Needs you / Failed / Running / Done / Idle；Done 10 分钟后自动变 Idle；任何 hook 事件都能创建或更新会话；推 `session.updated` 事件（#15）
- [x] 清理：pid 存活检测（每 30 秒，比对进程启动时间）+ 拿不到 pid 时 24 小时无事件兜底；`perch session rm <id>` 手动移除
- [x] `perch hook` 沿父进程链找到 agent 进程的 pid 并随事件上报；实测 Claude 桌面 App 会话能否找到（能：每个会话一个 `claude` 进程）
- [x] 重写 Claude Code / Codex 的 hook 映射：不再产生 waiting / notice，只保留白名单内 PermissionRequest 的 request（`meta.session_id` 挂会话）；Hermes 不改（#19，a8c1483；升级留下的旧 item 由 perchd 启动时清掉，aa26609）
- [x] `perch session ls [--json]` 显示状态；`perch session start|end` 保持兼容；标记已看（Done → Idle）的 op 供 M8 跳转用（`session_seen` / `perch session seen`；`perch session rm` 也已做）
- [x] 验收：真实 Claude Code 和 Codex 会话，`perch session ls` 状态流转正确；关掉终端 tab 后 30 秒内消失（Claude Code + Ghostty 已确认，#16）；`swift test` 通过（2026-10-08 和 M8 验收一起测完，#17）

## M8 — Agent 面板 UI

- [x] 收起态：总色点（Needs you 🟠 > Failed 🔴 > Running 🟢 呼吸 > Done 🔵 > Idle ⚪）+ 运行中会话数（0 不显示）；橙 / 红 / 蓝进入时脉冲（v0.3 起色点换成像素小怪物，#22）
- [x] 展开态：按状态分组、组标题带数量、空组不显示；每行色点 + 像素图标 + 项目名 + 时长 + 跳转，第二行随状态变化；结构留出以后加 tab 的位置
- [x] 12pt 单色像素 agent 图标（Claude Code 小怪物、Codex 仿 ChatGPT 的花结（24×24 细格）、Hermes 翅膀、未知机器人），点阵数据在 PerchAppCore 可测
- [x] 交互：点整行跳转并标记已看；Allow / Deny（白名单内）；⌥⇧A / D / O 作用于队首 Needs you；右键行 "Remove from Panel"；右键刘海只剩 Quit（#19，点击 / 右键 / 快捷键的 UI 路径待 #20 人工验收）
- [x] 刘海上的 todo UI 下线：task 行、快速录入（⌥⇧Space、New Task）、到期提醒与系统通知；Claude Code / Codex 的 hook 不再发 waiting / notice item（#19）
- [x] 核实全屏 App 下刘海的表现：可见、能悬停展开、能看到脉冲（2026-10-08，Ghostty 全屏）
- [x] 验收：真实会话下颜色、数量、分组、跳转、审批都正确；CLI 到刘海 ≤ 200 ms（2026-10-08，#20；延迟均值 14 ms）

## M9 — Hermes 迁到会话模型（⏸ 搁置：2026-10-08 起先只支持 Claude Code 和 Codex）

- [ ] 单独设计（每轮都有 `on_session_end`、gateway 会话没有关闭、进程常驻不能做 pid 检测），M8 验收后再定

## M10 — 零配置安装（#25：#26 / #27 / #28 / #29）✅ v0.4.0

- [x] `perch setup` / `perch uninstall`、固定安装位置 `~/.perch/bin`、`agents.json`、自修复、v0.3 迁移（#26）
- [x] App 自检、首次运行设置卡片、设置行、Agents 子菜单、Codex 信任提示（#27，2026-10-10 用户验收）
- [x] 开机启动（`SMAppService`，ad-hoc 签名可用）和刘海里的 "Uninstall Perch…"（#28）
- [x] Homebrew cask（tap 就是本仓库）、README / 发版说明模板 / `install.sh` 改成新流程（#29）
- [x] 干净的 macOS 用户账户上，预编译 zip 端到端可用：过 Gatekeeper → 打开 → 设置卡片 → Connect → Claude Code 会话出现在刘海（2026-10-12，维护者本机 `--zap` 清空后用 Chrome 下载的 zip）
- [x] Codex：出现信任行；在 codex 里 `/hooks` 并开新会话后，Codex 会话出现、信任行消失（2026-10-12，第二台 Mac）
- [x] `brew install --cask` 从 tap 安装 → `perch` 在 PATH 上（Open Anyway 之后能跑）→ 打开 App 出设置卡片；`brew uninstall` 删掉 hook 和 perchd；`--zap` 连 `~/.perch` 一起删（2026-10-12 维护者本机；卡片在同一个 App 的 zip 安装上看到）
- [ ] 装着 v0.3 的机器只换 App 就能升级，除了 Codex 重新信任一次没有别的手动步骤（不测，2026-10-12 维护者定；有单元测试，本机 `0.4.0-dev` → `0.4.0` 换 App 正常）
- [x] 先装 Perch 后装 Codex，出现 "Codex found · Connect"（2026-10-12，第二台 Mac）
- [x] 重启后刘海回来（开机启动）；勾着 Open at login 注销再登录 Perch 在跑、出现在 登录项，菜单里取消后消失（#28；2026-10-12，第二台 Mac）
- [x] "Uninstall Perch…" 删掉 hook / launchd / `~/.perch/bin`，保留 `~/.perch`，App 进废纸篓（#28；2026-10-12，第二台 Mac 的真实安装）
- [x] README、CLAUDE.md、`project.md`、MILESTONES 描述新流程，不再有旧的手动步骤

## M11 — Grok Build（#31，v0.5 第一个新 agent，#24）✅

- [x] 实测 grok 1.0.50 的 hook：payload（camelCase + 部分 snake_case 副本）、`permission_prompt` 没有命令、`StopCancelled` 的 `reason` / `cancelledBy`、Ctrl+C 太早什么都不发、hook 的父进程就是 `grok`（2026-10-12）
- [x] 其他适配器看到 `GROK_HOOK_EVENT` 就退出（Grok 默认也跑 `~/.claude/settings.json` 的 hook）
- [x] `perch hook grok`：映射见 CLAUDE.md"Hook 适配"；子 agent 事件忽略；刘海永远不能批准 Grok
- [x] 状态机：报告带 `turn_id`，别的轮的结束报告丢掉（只存内存）；`settle`（`idle_prompt` 兜底）
- [x] 安装：`~/.grok/hooks/perch.json`（Perch 独占，不写备份，空了就删），按 `~/.grok` 检测；设置卡片 / 设置行 / Agents 菜单 / `perch setup` / `perch uninstall` 都带上 Grok
- [x] 刘海：Grok 的像素图标（斜线穿过的圆环）和名字
- [x] 验收：真实 grok 会话（Ghostty）——发 prompt → Running；要权限的命令 → Needs you + "Answer in the terminal"，在终端批准后回 Running；跑完 → Done；Ctrl+C → Idle；关 tab → 消失；点行跳回那个 tab；`~/.perch/hook.log` 干净（2026-10-12，维护者本机，`APPDIR=/Applications scripts/install.sh` 装的这个分支）
- [x] 验收：设置卡片 / "Grok found · Connect" 连上 Grok，断开后 `~/.grok/hooks/perch.json` 被删掉（2026-10-12，同上）

## M12 — Todo tab（#41：#42 / #43）

设计见 #41 和 `docs/PRD.md` 的"Todo tab"。

- [x] 优先级：schema v4（老数据都是 Normal）、`perch add|update --priority` / `-p`（值不对 exit 64）、`ls` / `todo.md` 按优先级排并标出 High / Low、HTTP 不带 `priority` 照常（#42）
- [x] 展开态 tab 栏：Agents（Needs you 橙点 / Failed 红点）和 Todo（灰色未完成数）；有 Needs you / Failed 时打开在 Agents，否则打开在上次选的 tab，重启后回到 Agents；打开着从不自己换 tab；高度跟着 tab、0.15 秒动画（#42）
- [x] Todo tab：标题和摘要、High / Normal / Low 分组（组内最老的在前）、点圆圈 3 秒后完成（Undo 可撤，收起后照样完成）、右键 Priority ▸（#42）
- [x] 收起态不受 todo 影响（#42；#56 起右翼多一个静态的 todo 图标和未完成数，仍不脉冲、不出声）
- [x] 弹窗：⌥⇧Space 在刘海下面打开、刘海保持收起；"+ Add a todo" 在面板下面打开、面板保持展开；Return 添加后保持打开、清空、回到 Normal；Tab / Shift-Tab 轮换优先级；输入什么存什么，空白不提交；Esc / 点别处关闭（#43）
- [x] 编辑和删除：双击标题 / Edit… 打开预填的弹窗，Return 保存标题和优先级、Esc 不改；Delete 立刻 `rm`；面板打开时新加的那一行高亮 1 秒（#43）
- [x] `QuickEntryHotKey` 可改快捷键（重启生效）（#43）
- [x] PRD、CLAUDE.md、`project.md`、MILESTONES、README 描述上线的行为（#43）
- [x] `swift build` / `swift test` 通过；数据模型的测试连真实的进程内 perchd
- [ ] 人工验收：终端在前台时 ⌥⇧Space 打开弹窗、打字进弹窗、Esc 后键盘回到终端；悬停、点击、切 tab 动画、"减少动态效果"、有刘海的屏上的条带
- [ ] 维护者真实用一天后验收

## M13 — Todo 搬进 Apple Reminders（#50：#51 / #52 / #53）

设计见 #50 和 `docs/PRD.md` 的"Todo tab"里的 Reminders 一节。

**#51 bridge**
- [x] `RemindersStore` 协议（PerchAppCore）是通往 EventKit 的唯一接缝；`EventKitRemindersStore`（PerchApp）尽量薄；测试用内存里的假 Reminders，从不碰真的
- [x] Todo tab 状态：Connect Reminders / Open System Settings / Create Perch list（列表被删后从不自动重建）/ 就绪，不在 iCloud 时 "Not syncing — no iCloud"；找列表按记下的标识符、再按名字（优先 iCloud）、都没有就建；隔离运行用 "Perch Dev"
- [x] `bridge_register`：perchd 同时只收一个 bridge，它断开时下一个报名的接手（watch 上广播 bridge 来去）
- [x] `todo_snapshot`：连上时、每次 Reminders 变化、自己写完立刻发；perchd 的只读缓存（task item）+ 短 id 引用表（`todo_refs`，schema v5），重写 `todo.md`、广播 watch 事件
- [x] 字段对应（优先级 1–4 High、0 / 5 Normal、6–9 Low；写 1 / 0 / 9）；刘海里完成（保留 3 秒 Undo）、添加、改优先级、删除直接写 Reminders，Perch 不管的字段不动
- [x] schema v5 删掉旧的 open / done task；等待中的 task、notice、request 不动
- [x] CLI 对 todo 的写一律失败（"Todo needs Perch.app running with Reminders access"、exit 1、`--json` 错误格式）；`inbox.md` 的行留在文件里（#52 再吸收）
- [x] 空状态只有 "All clear"
- [x] 签名：designated requirement `identifier "dev.perch.app"`；Info.plist 加 `NSRemindersFullAccessUsageDescription`
- [x] `swift build` / `swift test` 通过；CLAUDE.md、PRD 更新
- [x] 人工验收（真 Mac + iPhone，2026-10-16 维护者验收通过）：Connect 能用；手机 ↔ 刘海双向都能看到变化；重新编译的 App 保留 Reminders 权限
- [ ] 测量 App 写入 → `EKEventStoreChanged` 的延迟和真实的 iCloud 手机 → Mac 延迟，记在 #50 的评论里

**#52 CLI / inbox.md 经 bridge 写**
- [x] `add` / `done` / `update` / `rm`（和 `update --status dismissed`）对 todo 的写经 perchd 交给 bridge（`todo_op` → `todo_ack` → 快照），`ls` 马上看得到
- [x] 没有 bridge 或 2 秒内没等到：一行错误、exit 1、`--json` 错误格式，不排队；晚到的 ack 照样记 key，同 `--key` 重试不重复
- [x] `--due`（只有日期 / 带时间，`due_date_only`，schema v6）、`--link`、`--priority` 写进提醒；同 `--key` 再 add 是改；`--source` / `--meta` / `--expires` 对 todo 不存
- [x] 等待中的 task `update --status open` 搬进 Reminders（短 id、key 不变）；`ls --status done` 是 7 天内完成的，`update --status open` 重新打开
- [x] 不是 bridge 的 App 的 Todo tab 写经 perchd 交给 bridge
- [x] `inbox.md` 只在 bridge 连着时吸收，做完一行删一行；没有 bridge 或 bridge 做不了时留在文件里
- [x] 没有 bridge 时：`perch ls` stderr "Todos as of HH:MM — Perch.app isn't connected"、`--json` 的 `todos_as_of`、`todo.md` 的 As of 行；缓存是空的不说
- [x] `swift build` / `swift test` 通过；README、AGENT-SNIPPET、PRD、CLAUDE.md 更新
- [x] 人工验收（真 Mac，2026-10-16 维护者验收通过）：装好的 Perch.app 连着时 `perch add` / `done` / `rm` 改到 Reminders 和手机；退出 App 后 `perch add` 报错、`perch ls` 带 as of；`inbox.md` 的行在 App 打开后进 Reminders

**#53 日期、✎、大编辑器**
- [x] spike：`x-apple-reminderkit://REMCDReminder/<UUID>` 能打开那条提醒所在的列表；只设到期时间不加 alarm 就不会像 Reminders 那样提醒（Reminders 自己会加），结果记在 #50
- [x] 日期标签（Today / Tomorrow / 星期几 / "Oct 20" / 带年份、只有日期 / 带时间、过期白色），固定 now 和日历的测试；不改排序
- [x] 行：`○ 标题 … 日期 ✎`，悬停完整标题和日期；单击圆圈或标题完成，双击不多做；右键 Edit… / Priority ▸ / Delete
- [x] ✎ 打开那条提醒（找不到就只打开 Reminders），刘海收起
- [x] 大编辑器：标题、备注、日期、时间、优先级、URL；Return 保存、Esc 不改；Perch 不管的字段不动；备注进缓存
- [x] 设时间同时加 alarm（刘海和 CLI 都是），时间改了跟着走，别的 alarm 不动
- [x] 添加弹窗不变；`swift build` / `swift test` 通过；PRD、CLAUDE.md 更新
- [x] 人工验收（真 Mac，有 Reminders 权限，2026-10-16 维护者验收通过）：行的样子、✎ 跳过去、大编辑器（日期 / 时间选择器、Return / Esc / Tab）、在刘海里设的时间到点会提醒、iCloud 列表上 ✎ 也能找到那条

## M14 — 更多 Reminders 列表，按列表分组（#66：#69 / #70 / #71）

设计见 #66（父 issue）和 `docs/PRD.md` 的"Todo tab"、Reminders 一节。

**#69 数据通路、列表选择、Todo tab 和 CLI 按列表分组**
- [x] 列表选择存在 App 的 defaults（`RemindersOrder.<名字>` / `RemindersChecked.<名字>`，按 `calendarIdentifier`）："Perch" 永远勾选、位置可变；新列表排到最后不勾；不存在的默默不显示（选择里不删，回来照样勾着、位置不变）；改名的照样勾着、位置不变；隔离运行自己一套、只勾 "Perch Dev"；升级的用户只勾 "Perch"
- [x] "Perch" 的特殊处理不变（记下的 id → 名字、第一次自动建、从不自动重建、Connect / Open System Settings / Create Perch list）；别的勾选列表被删了就消失
- [x] 快照覆盖所有勾选列表（未完成 + 7 天内完成），每条带列表，加按顺序的列表描述（id、名字、iCloud）
- [x] perchd 把 todo 的列表记在 `meta`，列表描述存在 `daemon_state`（不改 schema），没有 bridge、重启后照样分组；`todo_refs` 从不删
- [x] Todo tab：每个勾选列表一组（按选择顺序、空的灰色 "All clear"）；组标题灰色列表名 + 数、不用列表颜色；不在 iCloud 的写 "Not syncing"；组内 High → Normal → Low、再创建时间、再 id
- [x] 摘要、tab 栏的数、收起态右翼的数（#56）都算所有勾选列表
- [x] 完成（带 Undo）、Edit…、Priority ▸、Delete、✎ 对任何勾选列表的 todo 都能用，只写它自己的列表，Perch 不管的字段不动；添加进 "Perch"
- [x] `perch ls` 按列表分组（再优先级、再创建时间；标出 High / Low），`--json` 带 `list`；`todo.md` 每个勾选列表一个小标题、空的 "All clear"；没有 bridge 时照样（"Todos as of HH:MM"）
- [x] `done` / `update` / `rm` / 重新打开 / `ls --status done` 对任何勾选列表都能用；`inbox.md` 和 `perch add` 进 "Perch"
- [x] 取消勾选只把那个列表的 todo 从 tab、`perch ls`、`todo.md` 拿掉，Reminders 不动；重新勾上短 id 不变；在 Reminders 里挪到没勾的列表就消失
- [x] 测试：假 Reminders + 真 perchd + `QueueModel`（`TodoListsTests` / `TodoListsCLITests`）、纯 `TodoList`（`TodoListTests`）、注入 `UserDefaults` 的选择（`ListSelectionTests`）
- [x] `swift build` / `swift test` 通过；PRD、CLAUDE.md、`project.md` 更新
- [ ] 人工验收（真 Mac，有 Reminders 权限）：`defaults write` 勾上别的列表后展开面板，分组、"All clear"、"Not syncing"、在别的列表里完成 / 编辑 / 改优先级 / 删除 / ✎ 都对；取消勾选再勾上短 id 不变

**#70 Lists… 窗口、添加弹窗和编辑器的列表选择、`--list`**
- [x] 先核实 EventKit：改提醒的 calendar 在同一个账户里外部标识符不变（macOS 15.6.1、iCloud 实测，记在 #70）；跨账户没法验证，Perch 拒绝跨账户挪
- [x] 右键刘海 → Lists…（只在有 Reminders 权限时）：不激活 App 的面板，每个列表一行（把手、勾选框、名字），按选择顺序；新列表在最下面不勾，删了的消失
- [x] 拖动改 Todo tab、`perch ls`、`todo.md` 的分组顺序；勾选 / 取消立刻生效；"Perch" 不能取消勾选但能拖
- [x] `perch add --list <名字>` 建在那个勾选列表里，不给是 "Perch"；`perch update <id> --list <名字>` 挪过去，短 id 不变
- [x] 没勾的、不存在的、重名的（精确、区分大小写）：一行错误列出勾选的列表、exit 非 0、`--json` 是 `{"ok":false,…}`、什么都不写；perchd 先拒绝，bridge 写的时候再查
- [x] `inbox.md` 照样进 "Perch"
- [x] 添加弹窗的列表选择器只列勾选的列表，每次打开都在 "Perch"
- [x] 大编辑器的 List 选择器挪 todo，不动它就不写列表（`TodoEditor.edited` / `ReminderChange(from:to:)`）
- [x] 测试：CLI `--list`（成功、每种拒绝、出错什么都不写）、bridge 再查、跨账户、假 Reminders 里挪列表、Lists… 的模型（`TodoListFlagTests` / `ListPickerTests`）、编辑器的列表 diff（`TodoEditorTests`）、选择的拖动和勾选持久化（`ListSelectionTests`）、按名字找列表（`ListNameTests`）
- [x] `swift build` / `swift test` 通过，`CONFIG=debug scripts/bundle-app.sh` 能编；PRD、CLAUDE.md、`project.md` 更新
- [ ] 人工验收（真 Mac，有 Reminders 权限）：右键 → Lists… 不抢终端焦点；拖动（包括 "Perch"）和勾选立刻改 Todo tab；"Perch" 的勾选框点不动；添加弹窗的选择器每次在 "Perch"、选了别的列表能加进去；编辑器换列表能挪、不动就不挪

**#71 优先级胶囊、Doing**
- [x] 每行 `○ 标题 … 日期 ▶ 胶囊 ✎`：胶囊写 High / Normal / Low，High 橙、Normal 灰（最淡）、Low 绿，点了什么都不做（改优先级仍是 Priority ▸ 和编辑器）
- [x] schema v7：`todo_refs` 加 `doing`（默认 false），v6 的库干净地迁移
- [x] `perch update <id> --doing` / `--no-doing` 直接在 perchd 里设和清，不经 bridge，Perch.app 没连着也能用；不是 open 的 todo 报错；要单独一次 update
- [x] `status` 仍是 `open`；JSON 每条 todo 带 `doing`；`perch ls` 和 `todo.md` 把 Doing 排在自己列表最前、标 doing
- [x] Todo tab 的 ▶ 设和清 Doing（不是 Doing 的行悬停时灰色出现，Doing 的行一直白色实心，整行浅底、标题加粗）；右键菜单和编辑器里没有
- [x] `TodoList` 每组按 Doing、优先级、创建时间、id 排
- [x] 可以同时任意多条 Doing
- [x] 快照里完成了（包括在 tab 里完成）、或列表还勾着却不在了（删了、在 Reminders 里挪到没勾的列表）就清掉；重新打开不回来
- [x] 挪到另一个勾选列表、取消勾选再勾上，Doing 还在
- [x] Doing 算未完成（摘要、tab 栏、收起态的数），摘要不提 Doing，收起态不变
- [x] 测试：假 Reminders + 真 perchd + `QueueModel` + 真 `perch`（`TodoDoingTests` / `TodoDoingCLITests`：有 / 没有 bridge、`ls` / `--json` / `todo.md` 的顺序、完成和删除时清掉、挪列表和取消 / 重新勾选时留着、不是 open 的拒绝、`QueueModel.toggleDoing`）、纯 `TodoList`（`TodoListTests.doingFirstThenPriorityThenAgeThenIdInEachList`）、v6 → v7 迁移（`StartupTests.migratingToV7AddsDoingToTodoReferences`）、线上格式（`ModelsTests.aTodoCarriesDoingOnTheWire`）
- [x] `swift build` / `swift test` 通过，`CONFIG=debug scripts/bundle-app.sh` 能编；PRD、CLAUDE.md、`project.md` 更新
- [ ] 人工验收（真 Mac，有 Reminders 权限）：胶囊的颜色和大小；悬停时 ▶ 出现（刘海面板不是 key 也能）、离开就消失、点了变白色实心、整行浅底加粗并移到列表最前、再点清掉；点胶囊什么都不做；Doing 的待办完成后再打开不是 Doing
