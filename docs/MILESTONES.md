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

- [x] 收起态：总色点（Needs you 🟠 > Failed 🔴 > Running 🟢 呼吸 > Done 🔵 > Idle ⚪）+ 运行中会话数（0 不显示）；橙 / 红 / 蓝进入时脉冲
- [x] 展开态：按状态分组、组标题带数量、空组不显示；每行色点 + 像素图标 + 项目名 + 时长 + 跳转，第二行随状态变化；结构留出以后加 tab 的位置
- [x] 12pt 单色像素 agent 图标（Claude Code 小怪物、Codex 仿 ChatGPT 的花结（24×24 细格）、Hermes 翅膀、未知机器人），点阵数据在 PerchAppCore 可测
- [x] 交互：点整行跳转并标记已看；Allow / Deny（白名单内）；⌥⇧A / D / O 作用于队首 Needs you；右键行 "Remove from Panel"；右键刘海只剩 Quit（#19，点击 / 右键 / 快捷键的 UI 路径待 #20 人工验收）
- [x] 刘海上的 todo UI 下线：task 行、快速录入（⌥⇧Space、New Task）、到期提醒与系统通知；Claude Code / Codex 的 hook 不再发 waiting / notice item（#19）
- [x] 核实全屏 App 下刘海的表现：可见、能悬停展开、能看到脉冲（2026-10-08，Ghostty 全屏）
- [x] 验收：真实会话下颜色、数量、分组、跳转、审批都正确；CLI 到刘海 ≤ 200 ms（2026-10-08，#20；延迟均值 14 ms）

## M9 — Hermes 迁到会话模型

- [ ] 单独设计（每轮都有 `on_session_end`、gateway 会话没有关闭、进程常驻不能做 pid 检测），M8 验收后再定
