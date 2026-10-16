# Perch · PRD v0.2

2026-09-24 · Webber（v0.1）· 2026-09-28 方向调整为 agent 面板（v0.2）· 2026-10-15 todo 作为 Todo tab 回来（#41）· 2026-10-16 todo 搬进 Apple Reminders 的 "Perch" 列表（#50）

## v0.2 方向调整（2026-09-28）

v0.1 的定位是"agent 等待队列 + 我的待办"。M1–M6 做完后调整为：**刘海是 agent 的灵动岛面板**，只显示 agent 会话的状态。

- **todo 暂时搁置**：刘海 UI 里拿掉 task、快速录入、到期提醒；daemon、SQLite、`perch add/ls/done`、`todo.md` / `inbox.md` 全部保留不动（CLI 契约不变）。以后作为展开态里一个**独立的 tab** 回来，不和 agent 面板混在一起。2026-10-15 回来了：展开态的 Todo tab（#41），只放人手写的待办、按优先级分组、不带任何时间，见下方"Todo tab"。
- **一行 = 一个 agent 会话**（按 `session_id`），从第一次发 prompt 到 SessionEnd，状态在五种之间流转（见下方"Agent 面板"）。
- **先接 Claude Code 和 Codex**（2026-10-12 起加 Grok Build，#31：刘海不能批准 Grok，只提示去终端回答）；Hermes 的会话生命周期不同（每轮都发 `on_session_end`、gateway 会话没有"关闭"、进程常驻），暂不显示，单独一个里程碑迁移。
- 本文下方凡是和"Agent 面板"一节冲突的 v0.1 描述（收起态数字 = 待办数、notice、快速录入等），以"Agent 面板"为准。

## 定位与原则

**Agent 的灵动岛**：住在 MacBook 刘海里的 agent 状态面板。一眼看到每个 agent 会话在跑、在等你、跑完了还是出错了。核心闭环：agent 在等你 → 刘海亮 → 你就地处理或跳回去。

iPhone 灵动岛的三个原语直接映射到 agent：

| 灵动岛原语 | 在本产品中的对象 | 刘海上的表现 |
| --- | --- | --- |
| Live Activity（正在进行的事） | 每个 agent 会话及其状态 | 收起态：总状态色点 + 运行中会话数；展开态：按状态分组的会话列表 |
| Alert（需要你处理） | agent 等权限、等回答、出错 | 橙 / 红色脉冲，展开后排在最前 |
| Control（就地操作） | 批准 / 拒绝权限请求、跳回终端 | 展开态的内联按钮和全局快捷键 |

音乐控制、系统 HUD、文件中转全部不做，这是和现有刘海应用的切割线。

四条设计原则：

1. **Agent-first**：收起态只有 agent；人手写的待办放在展开态独立的 Todo tab（#41），不影响收起态的小怪物、数字、横幅和声音。
2. **Local-first**：单机、单用户、无云端，daemon 和数据都在本地。
3. **CLI 是唯一契约**：任何能跑 shell 的 agent 零学习成本接入，存储是实现细节。
4. **第一版砍掉一切非核心**：先自用跑通，但 CLI 契约、数据模型、hook 适配器按可开源分发的形态设计。

## 背景：为什么是这个位置

刘海应用已是一个小品类，2026 年至少有 13 家在做，几乎全部围绕音乐控制、系统 HUD、文件中转；待办只有 NotchDo、NotchOwl 两家专门做，且都是人手写的个人 todo。没有一家把刘海当作人和 AI agent 之间的界面。

刘海是屏幕上唯一永远可见、不占空间的位置。同时开着多个终端跑 Codex、Claude Code、Hermes 时，它们的状态散在各自的窗口里，"哪个 agent 在等我"这个问题目前没有任何地方能一眼看到。

两个早期信号说明有人在往这边摸，但都还是附加功能而非主线：[MacNotch](https://macnotch.io/) 加了一个"AI coding agent 监控"模块，只读；[h4ckm1n-dev/atoll](https://github.com/h4ckm1n-dev/atoll) 把 Atoll fork 成"AI coding agent 的原生伴侣"，做了内联 diff 和 plan mode 展示。

技术上的窗口期也到了：Claude Code 和 Codex 都已提供阻塞式的 `PermissionRequest` hook，外部程序可以在权限提示弹出前替用户做决定。这让"在刘海里批准"从设想变成了一个脚本的事。

## 核心场景

三个场景覆盖 v0.1 的全部功能，前两个是主线。

**场景一：agent 请求权限**。Claude Code 在第二个终端里要执行 `npm test`，`PermissionRequest` hook 触发，刘海变橙色并脉冲一次。悬停展开，看到"claude-code · 等待权限：npm test · 12 秒前"和完整命令原文。命令在白名单内，点 Allow 或按 ⌥⇧A，hook 返回 allow，终端里不弹提示，agent 继续跑。如果命令是 `rm -rf build/`，刘海只显示"去终端"，点一下跳回那个 session。

**场景二：agent 跑完了**。Codex 结束一轮，`Stop` hook 触发，刘海显示一条 notice"codex · 完成：PR #42 已推送"。看一眼后它到时自动消失；想跟进就点一下转成 task。收起态的 Live Activity 从"2 agents · 4m"变成"1 agent · 1m"。

**场景三：手写待办**。按全局快捷键，输入"回复 X 的邮件 @15:00"，回车。刘海数字加一。到 15:00 系统通知弹出，刘海脉冲，过时后颜色点变红。点标题完成。

## 范围

v0.1 只做一个闭环：agent 在等你 → 刘海亮 → 就地处理或跳回去。

**做**

- todo 底座：daemon + SQLite + CLI
- 刘海 UI：收起态、展开态、快速录入、实时更新
- Claude Code 和 Codex 的 hook 适配器（同一套脚本）
- Hermes 的接入（M6 定：Hermes 跑在本机，走 shell hook，同一个适配器；HTTP 端口留给容器里的客户端）
- 三个控制动词：approve、deny、open
- 刘海批准的安全白名单
- 时间提醒：系统通知 + 刘海脉冲

**不做，及原因**

| 不做 | 原因 |
| --- | --- |
| dispatch（从刘海往 agent 派任务） | 把产品从"响应 agent"变成"指挥 agent"，是第二条产品线，先把响应侧做扎实 |
| stop / cancel | Claude Code 和 Codex 没有干净的外部停止接口，只有 Hermes 能做，不值得为一个 agent 加动词 |
| reply（在刘海里回答 agent 的提问） | agent 提问走 `Notification` hook 的 `elicitation_dialog`，不阻塞，刘海接不到回答的口子；等官方给阻塞式提问 hook 再加 |
| MCP server | 三个目标 agent 都能跑 shell 或 HTTP，暂时没有需要 MCP 的场景 |
| markdown 双向同步 | daemon 持有 SQLite 时，手改文件再同步是冲突和重复 id 的集中产地；改为只读镜像 + 追加式收件箱 |
| 音乐控制、系统 HUD、文件中转 | 现有 13 家都在做，不是本产品的差异化 |
| 项目、标签、子任务、重复任务、拖动排序、"今天完成的" | todo 只是底座，不追求完整的任务管理 |
| Perch 自己的到期提醒、推迟、日历（Todo tab） | 提醒只由 Reminders 自己发一次（Perch 设时间时加的 alarm 也是 Reminders 发的，#53）；刘海里的时间不能和"agent 在等你"抢信号，收起态永远不管 todo。到期日期只在 Todo tab 的行里显示（#53），不参与排序 |
| notice 转 task（Todo tab） | notice 是 agent 的告知，不是人的待办；Todo tab 只放 "Perch" 列表里的待办 |
| agent 给人留 todo（agent 图标、跳回链接、给 agent 的说明） | Todo tab 只给人自己写的待办；`perch add` 不变，只是不推荐给 agent |
| 在刘海面板里直接打字、任何输入语法（优先级标记、`@15:00`） | 刘海面板永远不拿键盘焦点；打字只在单独的弹窗里，输入什么存什么 |
| 删除确认、删除撤销 | 删除很少误点，确认框比偶尔重写一条更烦 |
| 自己的同步、iPhone App、日历、多用户 | 不做自己的同步：多设备只通过 Apple Reminders 的 "Perch" 列表（#50），iCloud 负责同步；单用户 |
| 读 "Perch" 以外的 Reminders 列表、选别的列表、没有 Reminders 权限时的本地 todo | 一个列表就是一个真相；没有权限就没有 todo 功能 |
| Windows / Linux | 刘海是 Mac 硬件特性 |

无刘海的 Mac 上退化为顶部居中的小胶囊，成本很低，保留。

## 数据模型

一张表，控制请求完全复用待办的管道，不另开一套。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | string | 短、可手打，如 `t7k2` |
| title | string | 标题 |
| kind | enum | `task` 需要我行动 / `notice` 仅告知、到时自动消失 / `request` agent 在等一个决定 |
| status | enum | `open` / `waiting`（agent 在等我）/ `done` / `dismissed` |
| source | string | `human` / `claude-code` / `codex` / `hermes`；自由字符串，新 agent 不用改代码 |
| priority | enum | `high` / `normal` / `low`，默认 normal（2026-10-15，#41，schema v4）；Todo tab 按它分组，`perch ls` / `todo.md` 按它排序。todo 的优先级来自 Reminders（见"Todo tab"的 Reminders 一节） |
| due_at | datetime? | 到期时间。v0.2 起刘海不再用它（不显示、不提醒），只为兼容留在 CLI 和库里 |
| due_date_only | bool | `due_at` 是一整天（那天的零点）而不是某个时刻：只有日期的提醒（#52，schema v6）；JSON 里只在为 true 时出现 |
| link | string? | URL、文件路径或终端 session 引用，点一下跳回去 |
| meta | json? | agent 自由塞 cwd、session_id、工具名等 |
| created_at / updated_at | datetime | — |

`request` 类型多三个字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| options | string[] | 如 `["allow","deny"]` |
| response | string? | 用户选的值，hook 脚本等的就是它 |
| expires_at | datetime | 超时后 hook 不返回决定，终端原生提示接管 |

`kind` 里区分 task 和 notice 是因为"agent 完成了"不是待办，混在一个列表里会稀释橙色信号的含义。

**v0.2 新增 `sessions` 表**（M7，schema v2）。会话状态只放这里，不再用 item 表达：Claude Code / Codex 的 hook 不再产生 waiting / notice，item 表里只剩刘海可以回应的 request（hook 用 `--wait` 等它的回应值），request 通过 `meta.session_id` 挂到会话那一行。

| 字段 | 说明 |
| --- | --- |
| id | agent 自己的 `session_id` |
| source | `claude-code` / `codex` / …，决定像素图标 |
| title / cwd | 项目名（cwd 的目录名）和目录 |
| link | 跳回终端（`perch-terminal://…`） |
| status | `waiting`（Needs you）/ `failed` / `running` / `done` / `idle` |
| prompt | 本轮 prompt 的首行（运行中显示） |
| last_message | 最后一条回复的首行（完成 / 空闲显示） |
| detail | 等你时的详情：完整命令原文、原因、"去哪里回答" |
| error | 出错时的错误类型 |
| pid / pid_started_at | agent 进程和它的启动时间，用于存活检测（防 pid 复用） |
| started_at / turn_started_at / status_at / updated_at | 首次出现、本轮开始、进入当前状态、最后一次事件 |

清理：perchd 每 30 秒检查 pid，进程没了就移除；拿不到 pid 的会话 24 小时没有事件就移除；`perch session rm <id>` 和刘海右键可以手动移除（之后再来事件会重新出现）。

## 接口层

CLI 是唯一契约，daemon 是唯一真相，刘海 UI、CLI、Hermes 全是 daemon 的客户端。

```mermaid
flowchart LR
  CC[Claude Code hook] --> CLI[perch CLI]
  CX[Codex hook] --> CLI
  H[人 · 终端] --> CLI
  HM[Hermes shell hook] --> CLI
  CT[容器里的客户端] -->|localhost:port| D[daemon + SQLite]
  CLI -->|Unix socket| D
  D -->|事件推送| UI[刘海 UI]
  D -->|渲染| MD[todo.md 只读镜像]
  IB[inbox.md] -->|监听并吸收| D
  D <-->|todo 写 / 快照| BR[Perch.app = Reminders bridge]
  BR <--> RM[Reminders "Perch" 列表]
```

所有写入汇到 daemon，所有读取从 daemon 推出，没有任何客户端直接碰 SQLite。todo 是例外的一半：真相在 Reminders，daemon 把 todo 的写交给 bridge App 去做（#52），自己只存快照。

**CLI `perch`**

| 命令 | 作用 |
| --- | --- |
| `add "<title>" [--kind task\|notice\|request] [--source <s>] [--status waiting] [-p high\|normal\|low] [--due @15:00\|+30m\|2026-10-20] [--link <ref>] [--key <k>] [--wait]` | 新建；`--key` 幂等，同一 key 重复 add 不产生重复项；`--wait` 阻塞到 request 被回应或超时。open / done 的 task 是 todo，写进 Reminders（见下） |
| `ls [--status] [--source] [--kind] [--all] [--json]` | 列出；没有 bridge 时 todo 是旧快照，stderr 说明多旧 |
| `done <id>` / `done --key <k>` | 完成 |
| `update <id> [--title] [--kind] [--status] [-p] [--due\|--no-due]` | 修改；`--status open` 重新打开完成的 todo、把等待中的 task 搬进 Reminders，`--status dismissed` 删除 todo |
| `respond <id> <value>` | 回应 request |
| `rm <id>` | 删除 |
| `watch [--json]` | 流式输出事件，用于调试和第三方订阅 |
| `hooks install claude-code\|codex` | 一行安装 hook 适配器 |

全部命令支持 `--json`。配一份 5 行的 SKILL.md 片段（`docs/AGENT-SNIPPET.md`），塞进 AGENTS.md / CLAUDE.md 即可让 agent 主动使用。

**daemon**：launchd 常驻，SQLite 存储，暴露 Unix socket（本机 CLI 和 UI）和一个 localhost 端口（Hermes 容器通过 `host.docker.internal:port` 访问，和现有 webhook 架构一致）。事件通过 socket 广播推送，不轮询。

**文件**：`todo.md` 是 daemon 渲染的只读镜像，agent 可以 `cat`，也能进 git 或 Obsidian；`inbox.md` 是追加式收件箱，任何人往里写一行 `- [ ] xxx`，daemon 监听到就吸收进库并清空。两个文件都是单向的，没有双向同步。todo 搬进 Reminders 以后（#51），`todo.md` 的 "To do" 是 perchd 缓存的 "Perch" 列表；没有 bridge 连着时，"To do" 下面多一行 `_As of 2026-10-16 14:02 — Perch.app isn't connected_`，说明这是那时的快照（#52）。`inbox.md` 的行经 bridge 写进 Reminders（#52）：只有 bridge 连着时才吸收，一行一行地发，bridge 做完一行才从文件里删掉那一行；没有 bridge、或者 bridge 做不了（比如列表被删了），行就留在文件里，下次再试，永远不丢。

**同步**：Perch 不做自己的同步。todo 的唯一真相是 Reminders 的 "Perch" 列表，iCloud 把它同步到 iPhone 和别的设备；perchd 的 SQLite 里只有这个列表最近一次快照的只读缓存，加一张短 id 引用表，丢了能从 Reminders 重建（只是短 id 会重新分配）。这不是双向同步：只有一边是真相，缓存只由快照写。

## Hook 适配

四个事件，Claude Code 和 Codex 共用一套脚本，两家的 stdin JSON 结构、返回格式和默认 600 秒超时都一致（M5 核对：Codex 没有 `Notification`，多一个 `Interrupt`；实现以 CLAUDE.md 的"Hook 适配"为准）。

| 事件 | 触发时机 | 适配器做什么 | 是否阻塞 agent |
| --- | --- | --- | --- |
| `UserPromptSubmit` / `Stop` | 一轮开始、一轮结束 | 维护 Live Activity：哪些 agent 在跑、这一轮跑了多久（M3 定：按轮计时，不按会话） | 否 |
| `Notification`（matcher: `permission_prompt`、`elicitation_dialog`、`agent_needs_input`；M3 定：不接 `idle_prompt`，否则每轮结束都变橙） | agent 需要人 | `perch add --status waiting --key <session_id>`，刘海变橙 | 否 |
| `Stop` | 一轮结束 | resolve 同一 key 的 waiting，发一条 notice（带 `last_assistant_message` 摘要） | 否 |
| `PermissionRequest` | 权限提示弹出前 | `perch add --kind request --wait`，阻塞等刘海响应；拿到 allow/deny 后按各家格式打印 JSON 退出 | 是 |

`PermissionRequest` 的返回格式两家相同（M4 / M5 按官方文档核对）：`{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"|"deny","message":"…"}}}`。

刘海只是快捷通道，不是唯一通道：适配器等刘海的时间设为 15–30 秒，超时就不返回决定，终端的原生提示照常弹出。在终端前的人最多多等几十秒，不会被卡死。

**v0.2（M7）**：Claude Code / Codex 的事件改为驱动会话状态（见"Agent 面板"的状态表），不再产生 waiting / notice item；只有白名单内的 PermissionRequest 仍然发 request 等刘海。每个事件都带上 agent 进程的 pid（`perch hook` 沿父进程链找），供 perchd 做存活检测。Hermes 的映射没改；2026-10-08 起 Hermes 暂不支持（M9 搁置），只支持 Claude Code 和 Codex。

**v0.5（M11，#31）**：Grok Build 走同一个适配器 `perch hook grok`。Grok 没有 PermissionRequest，PreToolUse 的 `allow` 也不会跳过它的提示框，所以 Grok 不建 request，Needs you 只显示 Grok 的原话和"Answer in the terminal"（Grok 不说是哪条命令）。Grok 的取消报告可能晚于下一轮的 prompt，所以会话报告可以带轮次（`turn_id`），别的轮的结束报告丢掉。映射以 CLAUDE.md 的"Hook 适配"为准。

安装：`perch hooks install claude-code` 写 `~/.claude/settings.json`，`perch hooks install codex` 写 `~/.codex/hooks.json`（v0.4 起用户一般在刘海的设置卡片里点 Connect，写的是同样的 hook，见 #25）。Codex 的 hook 要在 codex 里用 `/hooks` 确认信任后才会跑。

~~Hermes 不走 hook，直接调 daemon 的 HTTP 接口~~。M6 改：Hermes 实际跑在本机（不在 Docker 里），有自己的 shell hook（`pre_llm_call` / `post_llm_call` / `pre_approval_request` 等），所以和 Claude Code、Codex 一样走 `perch hook hermes`。Hermes 的审批 hook 只能观察，刘海只能提示去哪里回答，不能批准。HTTP 接口保留，给够不着 Unix socket 的容器客户端。

Sources：[Claude Code hooks reference](https://code.claude.com/docs/en/hooks) · [Codex hooks](https://learn.chatgpt.com/docs/hooks)

## 安全规则

在几百像素的刘海里批准 `rm -rf` 是危险的，这是"控制台"和"看板"的根本区别。三条硬规则：

1. **展开态必须显示完整命令原文**，不截断、不摘要。命令过长时刘海展开区域可滚动，但不提供折叠。
2. **刘海是快捷通道，不是唯一通道**。hook 等刘海响应 15–30 秒，超时不返回决定，终端原生提示接管。任何情况下都不会因为刘海而默认放行。
3. **白名单之外不给批准按钮**。只显示"去终端"，点一下跳回去处理。

默认白名单按工具名和命令模式匹配，用户可改：

| 分类 | 刘海可一键放行 | 只能去终端 |
| --- | --- | --- |
| 文件 | Read、Glob、Grep | Write、Edit 到 `.env`、`~/.ssh`、`*.pem` |
| Bash | `npm test`、`pytest`、`cargo test`、`git status/diff/log` | `rm`、`sudo`、`git push --force`、`curl \| sh`、任何带 `>` 重定向到仓库外的命令 |
| 网络 | WebFetch、WebSearch | — |
| 其他 | — | 白名单未覆盖的一律去终端 |

白名单是一个本地配置文件，后续会是产品的一部分：每个团队对"什么可以盲批"的定义不同。

## Agent 面板（v0.2，M7 / M8）

### 会话与状态

一行 = 一个 agent 会话（按 `session_id`）。第一次发 prompt 时出现（不装 SessionStart，开了窗口没干活的会话不占位置），SessionEnd 或进程消失时移除。任何 hook 事件都能创建或更新会话。

| 状态（UI 文案） | 进入 | 离开 | 圆点 |
| --- | --- | --- | --- |
| **Needs you** | PermissionRequest / Notification（权限、提问） | PostToolUse(Failure)、刘海 Allow / Deny、UserPromptSubmit、Stop / StopFailure | 🟠 橙，进入时脉冲 |
| **Failed** | StopFailure（API 报错、限流等） | 下一次 UserPromptSubmit | 🔴 红，进入时脉冲 |
| **Running** | UserPromptSubmit；等你之后工具跑了 | Stop / StopFailure / 等你 | 🟢 绿，呼吸动画 |
| **Done** | Stop | 10 分钟后，或从刘海跳回那个终端 → Idle；下一次 UserPromptSubmit → Running | 🔵 蓝，静止，进入时脉冲一次 |
| **Idle** | Done 过期或已看过；Codex 的 Interrupt（Esc） | 下一次 UserPromptSubmit | ⚪ 灰 |

"等审批"和"等回答"合成一种 Needs you，行内文字区分。优先级：**Needs you > Failed > Running > Done > Idle**。

### 收起态

- **一个总状态**：取所有会话里优先级最高的状态。原来是一个色点，#22 起换成像素独眼小怪物（13×13 格，一格 1pt），身体是状态色，靠表情和动作区分状态：Running 小跑、眼珠左右扫；Needs you 抬眼看你、轮流挥手、天线尖白橙闪；Failed 眼里打 X、天线折弯、静止；Done 眯眼笑、静止；Idle 闭眼、旁边飘 z。没有会话是深灰、睡着；perchd 离线是半透明灰加离线图标。进入 Needs you / Failed / Done 时（原来的脉冲）播一次短反应：跳两下 / 抖一下 / 举手跳一下，用触发它的那个状态的样子和颜色，之后回到总状态。只在有东西动时重绘（≤ 5 fps，反应 14 fps），"减少动态效果"下只显示静止帧。展开态每行仍是小色点。
- **运行中会话数**：只数 Running，为 0 时不显示。
- 不再显示耗时（"· 4m"挪进展开态每一行）。
- **事件横幅**（2026-10-14）：右翼平时空着。进入 Needs you / Failed / Done（脉冲那一刻）时伸出来，显示项目名（状态色）+ 一行（命令或问题 / 错误 / 回复首行），放得下停 4 秒，放不下滚一遍到末尾再停，最长 12 秒，不循环。更紧急的盖掉不紧急的；那个会话离开这个状态或刘海展开时提前收起。**不做常驻滚动文字**：余光里一直动的东西会稀释橙色信号。
- **小怪物的第二段反应和闲时彩蛋**（2026-10-14）：进入反应在原来那段（和提示音对齐）之后多一段：Needs you 头边冒 "!"、Failed 摔倒冒烟再爬起来、Done 撒彩纸。Idle / 没有会话时每 4 分钟左右一个小彩蛋（打哈欠伸懒腰、左右张望、吹鼻涕泡）。"减少动态效果"下都不播。

### 展开态（悬停触发）

按状态分组，组标题带数量（`Needs you 1` / `Failed 1` / `Running 3` / `Done 2` / `Idle 1`），空组不显示。组内排序：Needs you 等得最久的在前；Running 按本轮开始时间；Done / Idle 最近的在前。展开态上方、刘海左边的条带是 tab 栏：Agents 和 Todo 两个图标（#41，见"Todo tab"）。

每行两行字：

```
● [像素图标]  perch                              4m   ⤴
             Refactor the session state machine…
```

| 状态 | 第二行 | 时间 |
| --- | --- | --- |
| Needs you（审批） | 完整命令原文 + Allow / Deny（白名单内）或 "Answer in the terminal: 原因"（白名单外、超时；安全规则不变） | 等了多久 |
| Needs you（提问） | agent 的原话（Notification 的 message），没有就 "Waiting for your answer" | 等了多久 |
| Failed | 错误类型 | 多久前 |
| Running | 本轮 prompt 的首行 | 本轮已跑多久 |
| Done | 最后一条回复的首行 | 多久前完成 |
| Idle | 同 Done，整行变暗 | 多久前 |

**agent 图标**：自己渲染的 12pt 像素点阵（代码里的字符串，SwiftUI `Canvas` 逐格画，不抗锯齿），一般 12×12 格，放不下的形状用 24×24 细格（每格半个点，Retina 上一个像素）。单色白，Idle 时随整行变暗。颜色只给状态圆点。不打包任何商标文件：Claude Code = 像素小怪物，Codex = 仿 ChatGPT 的六环花结（24×24；M8 验收时用户定，`>_` 认不出来），Hermes = 翅膀，未知 agent = 小机器人。新 agent 加一张点阵即可。

文案一律英文。

### 交互

| 操作 | 效果 |
| --- | --- |
| 点整行（Allow / Deny 按钮除外） | 跳回那个会话的终端（Ghostty 定位到 tab，其他终端激活 App）；Done 顺带变 Idle |
| Allow / Deny | 只在白名单内的审批上出现 |
| ⌥⇧A / ⌥⇧D | 批准 / 拒绝面板上第一个 Allow / Deny（排序最前、带 request 的 Needs you 会话）；没有就不注册，键照常打字 |
| ⌥⇧O | 跳到等得最久的 Needs you 会话；没有就不注册 |
| 右键某一行 | "Remove from Panel"：手动移除（进程检测失效时的逃生口） |
| 右键刘海 | Sounds（提示音总开关和每种状态的开关，#35）、Display（面板放在哪块屏，#37）、Quit Perch |

v0.2 时 todo 相关交互（点标题完成、⌥ 点推迟、notice 转 task、⌥⇧Space 快速录入、到期提醒）随 todo 一起从 UI 下线；2026-10-15 todo 作为 Todo tab 回来，交互见"Todo tab"（推迟、notice 转 task、到期提醒不回来）。

### 提醒

刘海脉冲（见状态表），加提示音（2026-10-12 起，#35）：进入 Needs you / Failed / Done 时各播一段小怪物的声音，和它的反应动作同步——Needs you 是两声往上扬的"Mrrp? Mrrp?"（在叫你），Failed 是"Uh-oh… bzzt"（往下掉的哀叹加天线短路），Done 是"Bwip! hehe"（跳一下、咯咯笑、一点闪光）。默认全开，右键刘海 → Sounds 可以整体关掉或按状态关。1 秒内只放更紧急的一个，同一会话同一种声音 10 秒内只响一次；连接时已有的状态不响。不发系统通知。全屏 App 下刘海照样可见、能展开、能看到脉冲（M8 实测）。

**实时性指标**：CLI / hook 调用到刘海更新 ≤ 200 ms，靠 daemon 推事件，不轮询。

## Todo tab（2026-10-15，#41 / #42 / #43；2026-10-16 起是 Reminders 的 "Perch" 列表，#50；日期、✎、大编辑器 #53）

展开态的第二个 tab："Perch" Reminders 列表里的待办（#50，见下方"Reminders"），按优先级分组。样子跟着 Sapphire 的刘海：黑底面板、粗大标题加一行灰色摘要、导航图标在刘海旁边的条带里。

**tab 栏**：展开时，刘海左边的条带换成两个图标：Agents（小怪物）和 Todo（清单）。当前 tab 白色，另一个灰色，点一下切换。无刘海屏的菜单栏胶囊展开时也有同一条。
- Agents 图标：有会话 Needs you 时带橙点，否则有会话 Failed 时带红点。
- Todo 图标：灰色的未完成数，0 时不显示。

**先看 agent**：有任何 Needs you 或 Failed 会话时，面板总是打开在 Agents；否则打开在上次手动选的 tab（只在内存里，重启后从 Agents 开始）。打开着的面板从不自己换 tab，圆点就是信号。面板高度跟着当前 tab，切换时 0.15 秒的高度动画（"减少动态效果"下没有动画），宽度不变。

**收起态不变**：小怪物、运行数、事件横幅、提示音都只管 agent。添加、完成、改优先级、删除待办（包括手机上改的、到期和过期的）都不会改变收起态。

**Todo tab 的内容**
- 粗大的 "Todo" 标题，下面一行灰色摘要："6 open · 2 high"；没有 High 时 "6 open"；没有未完成的就是 "All clear"（只有这一种空状态，#51）。列表不在 iCloud 里时后面加 "· Not syncing — no iCloud"。
- 没有 Reminders 权限或列表时，整个 tab 只有一行说明和一个按钮（见"Reminders"）。
- 只显示 open 的 task（notice、request、等待中的、做完的都不显示），按 High / Normal / Low 分组。组标题带数量、和 Agents 的组标题同一个样式、空组不显示；High 的组标题白色，其余灰色。**优先级不用颜色**：橙、红、绿、蓝只属于 agent 状态。
- 组内最老的在前；改了优先级的待办按创建时间排进新组。
- 每行一行：`○ 标题 … 日期 ✎`（#53）。标题太长尾部截断；悬停显示完整标题和完整日期（"Friday, October 16, 2026 at 15:00"）。没有来源、链接。
- 日期（有到期日期时）：灰色；今天是 "Today"，明天 "Tomorrow"，一周内是星期几（"Thursday"），再往后 "Oct 20"，不是今年的带年份（"Jan 5, 2027"），过去的日期也是这种写法；有时间的后面加时间（"Today 15:00"）。过期的是白色，从不用 agent 的颜色；只有日期的那天结束才算过期。日期不参与排序，仍然是优先级分组、组内最老的在前。标签由 `TodoList.dueLabel` 算（可注入 now 和日历）。
- ✎ 一直显示：点了用 Reminders 的链接 `x-apple-reminderkit://REMCDReminder/<本机标识符>`（EventKit 的 `calendarItemIdentifier`）打开那条提醒，Reminders 切到它所在的列表（macOS 15 实测，见 #50），刘海收起；找不到那条提醒时只打开 Reminders。备注、子任务、旗标、提醒等 Perch 不编辑的东西都在那里改。
- 列表超过面板最大高度时滚动；底部固定一行 "+ Add a todo"。

**交互**

| 操作 | 效果 |
| --- | --- |
| 点圆圈 | 打勾、标题划掉、出现 Undo；3 秒后在 Reminders 里完成，行消失。3 秒内点 Undo 或再点圆圈就取消，Reminders 不动。计时在刘海的数据模型里，不在视图里，所以刘海收起后照样完成；3 秒内退出 Perch，待办保持未完成 |
| 单击标题 | 和点圆圈一样：完成，带 3 秒 Undo（#53；整行都是好点的目标，点错了 Undo 就行） |
| 双击 | 什么都不多做：第二下落在系统的双击间隔里就忽略（`QueueModel.doubleClickInterval`），所以就是一次单击；过了间隔再点才是 Undo |
| ✎ | 在 Reminders 里打开那条提醒，刘海收起 |
| 右键 → Edit… | 打开大编辑器（#53），预填 |
| 右键 → Priority ▸ | High / Normal / Low，当前的打勾；改完移到新组 |
| 右键 → Delete | 立刻删掉那条提醒，不确认；它进 Reminders 的"最近删除" |
| "+ Add a todo" | 打开弹窗（添加），面板保持展开，弹窗在面板正下方 |
| ⌥⇧Space（任何地方） | 打开弹窗（添加），在刘海正下方，刘海保持收起；再按一次关掉。`defaults write dev.perch.app QuickEntryHotKey "ctrl+opt+n"` 可改，重启生效 |

**弹窗**：刘海面板永远不拿键盘焦点，所有打字都在单独的弹窗里：添加用小弹窗，编辑用大编辑器（#53）。它是不激活 App 却能成为 key window 的面板（M2 快速录入同一个技巧），所以终端一直是前台 App；深色外观。
- 一个标题输入框，下面一排 High / Normal / Low 按钮，默认 Normal。Tab 选下一个优先级，Shift-Tab 上一个，按钮也能点（输入法正在组字时 Tab 留给输入法）。
- **不解析**：去掉首尾空白后原样存成标题，没有优先级标记、没有 `@15:00`。空白输入按 Return 什么都不做。
- 添加：Return 在 "Perch" 列表里建一条提醒（选中的优先级），弹窗不关、清空、回到 Normal，可以连续加。面板展开时新加的那一行高亮 1 秒。
- 编辑（#53）：大一点的同类弹窗，照着 Reminders 的详情做：标题、备注、日期开关加时间开关（打开日期是今天；打开时间是今天的下一个整点、别的日子 09:00）、High / Normal / Low、URL。Return 在任何一栏都保存并关闭（备注里 Shift / Option-Return 换行），Tab / Shift-Tab 在栏之间移动（备注里也是，不插入制表符），Esc 什么都不改。只写改了的字段；重复规则、子任务、标签、旗标、位置提醒、图片一律不动。备注随快照进缓存（`meta.notes`），编辑器才看得到。
- 时间会提醒：Reminders App 设了时间就同时加一个那个时间的提醒（alarm），只设 EventKit 的到期日期组件不会（#50 的 spike）。所以 Perch（刘海编辑器、`perch add --due @15:00`）设时间时也加一个那个时间的绝对提醒；时间改了，原来在旧时间的那个跟着走；变成只有日期或去掉日期时它也去掉。别的提醒（自定义时间、位置、相对的）不动。
- Esc 或点别处关闭。从面板打开时，面板在弹窗关闭前一直展开，关掉后恢复正常的悬停收起。
- 弹窗的状态（添加 / 编辑、标题、优先级、备注、日期、时间、URL、能不能提交）在刘海的数据模型里（`TodoEditor`），弹窗只负责画和转发按键。不是 bridge 的 App 编辑时经 perchd 交给 bridge（`update` 的 patch 多了 `notes` / `link` / `clear_link`）。

**CLI 和文件**：`perch add|update --priority high|normal|low`（`-p`），不给就是 Normal，值不对是用法错误（exit 64）。`perch ls` 和 `todo.md` 的 "To do" 按优先级排（High、Normal、Low，然后是原来的队列顺序），标出 High 和 Low。`inbox.md` 没有优先级语法，进来的都是 Normal。HTTP 客户端不带 `priority` 照常工作。#51 起 todo 来自 Reminders：`perch ls`、`todo.md` 照常显示（每条都有短 id，手机上加的也有）。

**CLI 写 todo（#52）**：`perch add`（open / done 的 task，任何 `--source`）、`done`、`update`、`rm`、`update --status dismissed` 对 todo 的写都经 perchd 交给 bridge：perchd 在 bridge 的 watch 连接上推一个带一次性 id 的 `todo_op`，bridge 写进 Reminders、回 `todo_ack`（id + 提醒的外部标识符）、再发快照，perchd 收到这份快照才回答 CLI，所以 `perch add` 之后马上 `perch ls` 一定看得到。
- 没有 bridge，或 2 秒内没等到：一行人类可读的错误、exit 1、`--json` 打印 `{"ok":false,"error":…}`，**不排队**。没有 bridge 时是 "Todo needs Perch.app running with Reminders access"；列表被删了是 "Perch list not found"；超时说明改动可能还会生效，先 `perch ls` 再重试。
- 晚到的 ack 照样记下引用和 key，所以超时后用同一个 `--key` 重试找到的是那条提醒，不会重复；不带 key 的重试可能重复，接受。
- 字段：`--key` 对 todo 照样幂等（同 key 再 add 就是改那条提醒，内容一样什么都不发）；`--due` 设提醒的到期日期组件，`2026-10-20` 只有日期，`@15:00` / `+2h` / ISO-8601 带时间；`--link` 设 URL；`--priority` 设优先级。`--source`、`--meta`、`--expires` 对 todo 不存。
- 等待中的 task 用 `perch update --status open` 变成 open（或 notice 用 `--kind task` 留下）：在 Reminders 里新建，本地那条删掉，短 id 和 key 不变。
- 完成的 todo：`perch ls --status done` 列出 7 天内完成的，`perch update --status open` 重新打开。
- 不是 bridge 的 App，Todo tab 的写也照这样经 perchd 交给 bridge。
- 没有 bridge 时读照常：`perch ls` 的 stdout 不变，stderr 多一行 "Todos as of 14:02 — Perch.app isn't connected"（不是今天就带日期）；`--json` 多一个顶层 `todos_as_of`，只在这种时候、且列出的东西里有 todo 时才有；缓存是空的就什么都不说。时间是缓存最后一次确定和 Reminders 一致的时刻：最后一份快照，或 bridge 断开的那一刻，perchd 重启后还记得（schema v6）。
- request、notice、等待中的 task 照旧是 perchd 自己的，不进 Reminders。

**Reminders（#50 / #51）**：todo 的唯一真相是 Reminders 里叫 "Perch" 的列表（隔离运行，即设了 `PERCH_HOME`，用 "Perch Dev"）。
- 只有 Perch.app 拿得到 Reminders 权限（launchd 起的 perchd 拿不到），所以 App 是 **bridge**：连上 perchd 后用 `bridge_register` 报名，perchd 同一时间只收一个，后来的 App 是普通客户端，bridge 断开时下一个报名的接手。bridge 把列表的完整快照（未完成的，加 7 天内完成的）用 `todo_snapshot` 发给 perchd：连上时、每次 `EKEventStoreChanged`、自己每次写完立刻发（不等通知）。perchd 对比缓存，给新提醒分配短 id，删掉不在快照里的，重写 `todo.md`，在 watch 上广播。
- bridge 的 Todo tab 直接写 Reminders：完成、添加、改优先级、删除。完成重复提醒按 EventKit 自己的做法。Perch 不管的字段（备注、日期、URL、提醒、重复、子任务、旗标、标签、图片）写的时候一律不动，也不往提醒里写任何 Perch 专用的标记。
- 字段对应：标题 ↔ title；优先级 1–4 读作 High、0 和 5（Medium）读作 Normal、6–9 读作 Low，写的时候 High → 1、Normal → 0（无优先级）、Low → 9；完成 ↔ done；到期日期组件 ↔ `due_at`（只有日期时是那天的零点，加 `due_date_only: true`）；URL ↔ link；创建时间 → `created_at`。
- 找列表：先按记下的标识符（App 的 defaults，改名也找得到），再按名字（优先 iCloud 的），都没有就在新提醒的默认账户里建。
- Todo tab 的状态：没问过权限 → "Connect Reminders"（点了弹系统提示，再找或建列表）；拒绝或受限 → "Open System Settings"（打开 隐私与安全性 → 提醒事项）；有权限但列表被删了 → "Create Perch list"（**从不自动重建**）；就绪，列表不在 iCloud 时摘要后面写 "Not syncing — no iCloud"。首次运行的设置卡片不变，只管 agent。
- 签名：Perch.app 是 ad-hoc 签名，designated requirement 是 `identifier "dev.perch.app"`（不是默认的 cdhash），所以重新编译、升级都保留 Reminders 权限。已知风险：任何自称这个 bundle id 的 App 都会继承权限；自签证书或 Developer ID 留到公开分发之前（见 CLAUDE.md 未决问题）。Info.plist 有 `NSRemindersFullAccessUsageDescription`；hardened runtime 没开，不需要 entitlement。

## 技术路线

Swift 全栈，一种语言：SwiftUI 做刘海 UI，daemon 和 CLI 用 Swift ArgumentParser 打成单二进制，SQLite 直接用系统 libsqlite3（M1 定，不用 GRDB）。

刘海窗口那套 NSPanel 技巧不自己写：[NotchDo](https://notchdo.app/) 是 MIT 协议，又正好是"刘海里的待办"，拿它的窗口层，换掉数据层。[Boring Notch](https://github.com/TheBoredTeam/boring.notch) 是 GPL-3.0，借它的代码会把整个项目锁成 GPL，产品化时是麻烦，不用。[luifon/notch-widget](https://github.com/luifon/notch-widget) 的 `CGSSpace.swift` 是 MPL-2.0，可以单文件引用。

系统要求 macOS 14+，与三家主流刘海应用一致。

## 构建顺序

v0.1 六个里程碑 + v0.2 三个，每一步都能独立验证再往下走；第三步完成时产品已经能日常使用。详见 `MILESTONES.md`。

| # | 里程碑 | 验证方式 |
| --- | --- | --- |
| 1 | daemon + CLI + SQLite + `watch`，不带 UI | 两个终端互相 `add` 和 `watch`，确认事件延迟和 `--key` 幂等 |
| 2 | 刘海 UI，借 NotchDo 窗口层 | 收起 / 展开 / 快速录入 / 点完成，CLI 到 UI ≤ 200 ms |
| 3 | Claude Code 的 `Notification` / `Stop` / `SessionStart` 适配 | 跑一个需要权限的任务，刘海变橙；跑完后 notice 出现并自动消失 |
| 4 | `PermissionRequest` + 白名单 | 刘海里 Allow 一次 `npm test`，终端不弹提示；`rm` 只显示"去终端"；超时后终端提示正常弹出 |
| 5 | Codex 复用同一套脚本 | 同步骤 3、4，只改返回 JSON 的分支 |
| 6 | Hermes 接入（M6 改为 shell hook） | Hermes 一轮 → Live Activity + notice；危险命令等审批时刘海变橙，回应后消失 |
| 7 | 会话状态机：`sessions` 表、pid 存活检测、Claude Code / Codex 的 hook 映射重写（不动 UI） | 真实 Claude Code 和 Codex 会话，`perch session ls` 状态流转正确；关掉终端 tab 30 秒内消失 |
| 8 | Agent 面板 UI；刘海上的 todo UI 下线 | 真实会话下颜色、数量、分组、跳转、审批都正确；CLI 到刘海 ≤ 200 ms |
| 9 | Hermes 迁到会话模型（单独设计） | 待定 |

`todo.md` 镜像和 `inbox.md` 收件箱放在第 1 步和第 2 步之间，工作量小，不单列。

## 未决问题与产品化余地

- [x] `link` 跳回终端的机制：日常用 Ghostty。Ghostty ≥ 1.3 可 AppleScript：提交 prompt 时记下聚焦的 terminal id，跳转时 focus 它；其他终端只激活 App。
- [x] 产品名 Perch（栖），CLI `perch`：agent 停在刘海上等你。
- [x] 全局快捷键默认值：快速录入 ⌥⇧Space（2026-10-15 起打开 todo 弹窗，#43）。
- [x] hook 等刘海的超时：先用 20 秒（可改），用一周后再看。

产品化余地：这个品类里 13 家全在做音乐控制，"agent 的灵动岛"的位置是空的。护城河不在 UI，在 hook 适配器目录和安全白名单——每多支持一个 agent 就是一个适配器，开源 CLI 加适配器目录天然是面向 Claude Code / Codex 用户的分发方式。自用跑通前不展开。
