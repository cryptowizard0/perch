# Perch — CLAUDE.md

Perch（栖）：住在 MacBook 刘海里的 agent 灵动岛面板——一眼看到每个 agent 会话在跑、在等你、跑完了还是出错了。
核心闭环：**agent 在等你 → 刘海亮 → 你就地处理或跳回去。**
产品需求见 `docs/PRD.md`，里程碑与验收标准见 `docs/MILESTONES.md`，**当前进度、下一步计划和交接说明见 `project.md`（新 session 先读它）**。先自用，但按可开源分发的形态设计。

**2026-09-28 方向调整（v0.2）**：todo 暂时从刘海 UI 拿掉（底层和 CLI 不动；2026-10-15 作为 Todo tab 回来，见下）；刘海只显示 agent 会话，一行一个会话，五种状态 Needs you 🟠 / Failed 🔴 / Running 🟢（呼吸）/ Done 🔵 / Idle ⚪。会话从 M7 起进 SQLite（`sessions` 表，状态机已实现，#15）。完整设计见 `docs/PRD.md` 的"v0.2 方向调整"和"Agent 面板"。

**2026-10-12（#35）**：加提示音。进入 Needs you / Failed / Done（就是刘海脉冲的那些变化）各播一段合成的小怪物声音，默认全开，右键刘海 → Sounds 可关；逻辑在 `PerchAppCore/Chime.swift`。仍不发系统通知。

**2026-10-14（#37）**：多屏时选面板放在哪块屏。右键刘海 → Display：Automatic（默认，有刘海的内建屏，没有就主显示器）/ Main Display（带菜单栏的那块）/ 某块具体的屏（按显示器 UUID 记在 defaults 的 `Display` / `DisplayName`，没连上时退回 Automatic）。没刘海的屏上是菜单栏里的胶囊；逻辑在 `PerchAppCore/Display.swift`。

**2026-10-14（#39）**：收起态右翼平时空着（#56 起放 todo 图标和数，见下）；进入 Needs you / Failed / Done（脉冲那一刻）时伸出来几秒，显示项目名 + 一行（命令 / 错误 / 回复首行），太长滚一遍就停，不做常驻滚动（`PerchAppCore/Banner.swift`）。进入反应多一段（"!"、摔倒冒烟、彩纸），Idle / 没会话时每 4 分钟左右一个小彩蛋（哈欠、张望、鼻涕泡），都在 `Mascot.swift`。#59（#58 的第 1 步）起 Failed（叹气、揉脑袋）和 Done（摇摆、哼歌）也有，按心情各抽各的（`Mood.quirks`），X 眼 / 笑眼和身体颜色从不变，只在播的时候重绘。#60 起小怪物知道过了多久：`Mascot.frame` 多一个 `since`（`Panel.signalSince`，Running = 最早开始的那一轮），一轮跑过 10 分钟头边挂汗滴、每 6 秒擦一下额头；Needs you（`since` = 等得最久的那个）1 分钟起两手一起挥、跳，5 分钟起每 8 秒敲三下玻璃，之后不再变（#61）。回答后（`QueueModel.respond`，面板按钮和 ⌥⇧A / D）Allow 鞠躬、Deny 挠头（#62）：收起时马上播，展开时等收起、5 秒内才播（`AnswerReactions`），没有横幅和声音，脉冲来了就让位。指针在 250pt 内时眼珠看它（#63，`Gaze` / `GazeTracker`，全局 + 本地 `.mouseMoved` 监听，不要辅助功能权限，"减少动态效果"下不装）：Failed 不看，睡着 / Idle 半睁眼偷看，反应、彩蛋、眨眼优先。#64 起 Done 的横幅（只在没有会话 Needs you / Failed 时）由小怪物扛过刘海：跳一下、钻进刘海、从右翼出来拉开横幅、站在末端摇摆撒彩纸、时间到了卷着横幅跑回去（`DoneRun` 纯路线，`QueueModel.flight`，`FlightView` 画在整条带子上，右翼多 15pt）；Needs you / Failed 来了冲回去，又一个 Done 原地跳、换横幅，展开就结束，"减少动态效果"下不飞。

**2026-10-15（#41 / #42 / #43，M12）**：todo 作为展开态的 **Todo tab** 回来，只放人手写的待办，任何地方都没有日期和时间（#50 起改了：到期日期来自 Reminders，`perch add --due` 能设（#52），Todo tab 的行显示日期是 #53）。展开时刘海左边的条带是 Agents（小怪物，Needs you 橙点 / Failed 红点）和 Todo（清单，灰色未完成数）两个图标；有 Needs you / Failed 会话时总是打开在 Agents，否则打开在上次手动选的 tab（只在内存里），打开着从不自己换 tab。Todo tab 按 High / Normal / Low 分组（优先级不用颜色；#71 起推翻了：每行一个带颜色的优先级胶囊，见下），组内最老的在前（#69 起改成按 Reminders 列表分组，组内按优先级、再按创建时间，见下）；点圆圈 3 秒后 `done`（Undo 可撤，计时在 `QueueModel`，收起后照样完成）；右键 Edit… 编辑（#53 起单击标题也是完成、双击不编辑，见下），右键 Priority ▸ / Delete（立刻 `rm`）。**刘海面板永远不拿键盘焦点**：打字只在单独的弹窗里（不激活 App 却能成为 key 的 `NSPanel`，`PerchApp/TodoPopup.swift`），⌥⇧Space 在刘海下面打开（刘海保持收起），"+ Add a todo" 在面板下面打开（面板保持展开）；输入什么存什么，不解析。收起态（小怪物、运行数、横幅、声音）只管 agent，todo 永远不影响它（#56 起唯一的例外：右翼的静态 todo 图标和数，见下）。逻辑在 `PerchAppCore` 的 `PanelTab` / `TodoList` / `TodoEditor` 和 `QueueModel`。设计见 `docs/PRD.md` 的"Todo tab"。

**2026-10-16（#50 / #51，M13）**：todo 的唯一真相搬到 Apple Reminders 里叫 **"Perch"** 的列表（隔离运行，即设了 `PERCH_HOME`，用 "Perch Dev"），iCloud 把它同步到手机；上面 #41 说的"只放人手写的待办"从此是"放 "Perch" 列表里的待办"。只有 Perch.app 拿得到 Reminders 权限（launchd 起的 perchd 拿不到），所以 App 是 **bridge**：`bridge_register` 报名（perchd 同时只收一个，断开时下一个接手），把列表的完整快照（未完成 + 7 天内完成的）用 `todo_snapshot` 发给 perchd（连上时、每次 `EKEventStoreChanged`、自己写完立刻发），自己的 Todo tab 直接写 Reminders（完成、添加、改优先级、删除，#53 起还有大编辑器的备注、日期、时间、URL；Perch 不管的字段一律不动）。perchd 只存快照的只读缓存（open / done 的 task item，source `reminders`）和短 id 引用表 `todo_refs`（schema v5，迁移删掉旧的 open / done task）。Todo tab 没有权限或列表时只有一个按钮：Connect Reminders / Open System Settings / Create Perch list（被删的列表从不自动重建）；列表不在 iCloud 时写 "Not syncing — no iCloud"（#69 起改成那个列表的组标题上灰色的 "Not syncing"）；空状态只有 "All clear"。接缝是 `PerchAppCore/Reminders.swift` 的 `RemindersStore`，EventKit 实现在 `PerchApp/EventKitReminders.swift`；测试只用假 Reminders。

**2026-10-16（#53，M13）**：Todo tab 的行是 `○ 标题 … 日期 ✎`：日期灰色（Today / Tomorrow / 星期几 / "Oct 20"，不是今年带年份，有时间加 "15:00"），过期白色，从不用 agent 颜色，不参与排序（`TodoList.dueLabel`）；悬停显示完整标题和日期；单击圆圈或标题都是完成（3 秒 Undo），双击不多做什么；✎ 用 `x-apple-reminderkit://REMCDReminder/<calendarItemIdentifier>` 在 Reminders 里打开那条提醒并收起刘海，找不到就只打开 Reminders（macOS 15 实测，#50）。右键 Edit… 打开大编辑器（标题、备注、日期 + 时间开关、优先级、URL；Return 保存、Esc 取消，只写改了的字段，`TodoEditor.edited` + `ReminderChange(from:to:)` / `Request.Patch(from:to:)`），添加弹窗不变。备注在缓存的 `meta.notes`。设时间时同时加一个那个时间的绝对 alarm（Reminders App 也这么做，只设到期组件不会响），时间改了它跟着走，`ReminderChange.alarms` 是规则。

**2026-10-16（#52，M13）**：CLI、`inbox.md` 和不是 bridge 的 App 对 todo 的写都经 perchd 交给 bridge：perchd 在 bridge 的 watch 连接上推 `todo_op`（一次性 id），bridge 写进 Reminders、回 `todo_ack`、再发快照，perchd 收到那份快照才回答，所以 `perch add` 之后马上 `perch ls` 一定看得到。没有 bridge 或 2 秒内没等到就报错、不排队；晚到的 ack 照样记下 key，同 `--key` 重试不重复。`--due 2026-10-20` 是只有日期的到期（`due_date_only`，schema v6），`--link` → URL；`--source` / `--meta` / `--expires` 对 todo 不存；`perch update --status` 能把等待中的 task 搬进 Reminders（短 id 和 key 不变）、重新打开 7 天内完成的、`dismissed` 删除。`inbox.md` 只在 bridge 连着时吸收，bridge 做完一行才删那一行。没有 bridge 时 `perch ls` 在 stderr 说 "Todos as of HH:MM — Perch.app isn't connected"，`--json` 加 `todos_as_of`，`todo.md` 的 "To do" 下加一行 As of。逻辑在 `Service.planTodoWrite` / `recordTodoWrite` 和 `Daemon` 的 pending writes。

**2026-10-16（#56）**：收起态右翼平时放一个**静态**的 todo 图标（`checklist`）+ 未完成数（和 tab 栏同一个 `openCount`，完成中的 3 秒内还算），是 todo 在收起态唯一露面的地方：0 条、没有 Reminders 权限 / 列表、perchd 离线时只有调暗的图标（`QueueModel.collapsedTodoCount` 为 0），有数时和运行数一样白；从不用状态色，不脉冲、不出声、不改小怪物、不出横幅，数变了也没动画；横幅出现时盖掉它（淡入淡出），收起后回来；没有交互和 tooltip，悬停和展开打开哪个 tab 照旧；没刘海的胶囊上一样。两翼对称，都取左右内容里宽的那边（`NotchGeometry.collapsedWing(runningCount:online:todoCount:)`，只有小怪物和图标时 27pt）。

**2026-10-19（#69，M14）**：Todo tab 和 CLI 显示所有**勾选的** Reminders 列表，按列表分组，不再只有 "Perch"（父 issue #66，Lists… 窗口和 `--list` 是 #70，见下；Doing 和优先级胶囊是 #71，见下）。勾选和顺序是 App 的 defaults，按 `calendarIdentifier` 记、按列表名分命名空间（隔离运行的 "Perch Dev" 自己一套）：`RemindersOrder.<名字>` 是所有已知列表的顺序、`RemindersChecked.<名字>` 是勾选的，都是字符串数组（`PerchAppCore/Reminders.swift` 的 `ListSelection`）；"Perch" 永远勾选、位置可变，新列表排到最后不勾，眼下不存在的列表（删了，或 EventKit 一时没列出来）不显示但 defaults 里从不删（回来时照样勾着、位置不变），改名的照样勾着、位置不变；升级的用户只勾 "Perch"，什么都不变。#70 起在 Lists… 窗口里改（见下），CLI 和 perchd 改不了。"Perch" 的特殊处理不变（先按记下的 id、再按名字找，第一次自动建，从不自动重建，`RemindersState` 只描述它）；别的勾选列表只读写，被删了就消失；"Perch" 没了时别的勾选列表照样进快照。`todo_snapshot` 带所有勾选列表的提醒（未完成 + 7 天内完成的，每条带 `list`）和按顺序的列表描述（`lists`：id、名字、是否 iCloud）；perchd 把每条 todo 的列表记在 `meta`（`list_id` / `list_name`），把列表描述存在 `daemon_state` 的 `todo_lists`（不改 schema），在 `list` 的回答里带 `todo_lists`，变了就在 watch 上先推 `todo_lists` 再推这份快照的 item 事件。写一律写到 todo 自己的列表（Todo tab 直接写、CLI 经 `todo_op`，`TodoOperation.seenInList`（线上 `seen_in_list`）是 perchd 上次看到它的列表，只是提示、不是目标，bridge 先找那里、再找别的勾选列表）；新建的默认进 "Perch"（#70 起添加弹窗和 `perch add --list` 能选别的勾选列表，`inbox.md` 永远进 "Perch"）。取消勾选只是从快照里拿掉（Reminders 不动），`todo_refs` 从不删，所以重新勾上短 id 不变；在 Reminders 里挪到没勾的列表就从 Perch 消失。`TodoList`：每个勾选列表一组（空的也有，灰色 "All clear"），按选择顺序；组内（#71 起 Doing 在最前）优先级 High → Normal → Low、再创建时间、再 id，到期日期不参与排序；组标题是灰色列表名 + 未完成数（和 Agents 的组标题一样，不用列表颜色），不在 iCloud 的列表标题上写灰色 "Not syncing"；`openCount` / `highCount` 跨所有列表，所以摘要、tab 栏的数和收起态的数（#56）都算全部。`perch ls` 的 open todo 按列表分组（每组前一行 `[列表名]`），组内优先级、再创建时间（到期日期不再排序），`--json` 的 todo 带 `list`（列表名）；`todo.md` 的 "To do" 下每个勾选列表一个 `###` 小标题，空的写 "All clear"；没有 bridge 时照样按缓存分组（"Todos as of HH:MM"）。

**2026-10-19（#70，M14）**：选列表、在列表之间挪 todo。右键刘海 → **Lists…**（只在有 Reminders 权限时出现）打开一个和添加弹窗一样的不激活 App 的面板（复用 `TodoPopupPanel`，`PerchApp/ListsWindow.swift`）：每个 Reminders 列表一行（拖动把手、勾选框、名字），按选择的顺序；勾选和拖动立刻生效（`QueueModel.setListChecked` / `reorderLists` → `ListSelection.setChecked` / `reorder` → bridge 发快照），Todo tab、`perch ls`、`todo.md` 跟着变；"Perch" 的勾选框锁死但能拖；新列表在最下面不勾，删了的消失；`reorder` 只换窗口里显示的那些列表的位置，一时不在的列表位置不变。`perch add --list <名字>`（默认 "Perch"）建在那个勾选列表里，`perch update <id> --list <名字>` 挪过去（短 id 不变）；名字精确匹配、区分大小写，没勾的、不存在的、重名的一律报错（一行，列出勾选的列表名，exit 非 0，`--json` 是 `{"ok":false,…}`），什么都不写；perchd 按最近一份快照的 `todo_lists` 先拒绝（`ReminderList.checked(named:in:)`，perchd 和 bridge 共用），bridge 写的时候再按自己的勾选查一遍；`--list` 只对 todo 有效。线上：`Request.list` / `Patch.list` 是列表名，`ReminderChange.list`（`todo_op` 里的 `change.list`）是目标列表的 id——新建进那里、改的时候挪过去；`seen_in_list` 仍只是查找提示。添加弹窗的标题栏右边有列表选择器（只在勾选了不止一个列表时出现），每次打开都回到 "Perch"（弹窗开着连续加时留在选的列表）；大编辑器多一行 List，只列能挪去的勾选列表，只在改了时写（`TodoEditor.list`，`edited` 写 `meta.list_id` / `list_name`，`ReminderChange(from:to:)` / `Patch(from:to:)` 带上它）。EventKit 改提醒的 calendar 在同一个账户里外部标识符不变（2026-10-19 macOS 15.6.1 在 iCloud 里实测，结果在 #70 的评论），跨账户（iCloud ↔ 本机）没法验证（这台 Mac 只有 iCloud），所以 Perch 拒绝跨账户挪（`ReminderList.account` = EventKit 的 `sourceIdentifier`，`moveRefusal`，"move it in the Reminders app"），编辑器也不列那些列表；在 Reminders 里跨账户挪了，短 id 可能变。

**2026-10-19（#71，M14）**：Todo tab 的行变成 `○ 标题 … 日期 ▶ 胶囊 ✎`。**优先级胶囊**（推翻 #41 / #42 的"优先级不用颜色"）：每行都有，写 High / Normal / Low，底是同色半透明胶囊，High 橙、Normal 灰（最淡：底约 10% 白、字 50% 白）、Low 绿（和 Needs you / Running 同色，接受：胶囊只在 Todo tab），只显示、不能点（改优先级仍是右键 Priority ▸ 和大编辑器；`PerchApp/TodoViews.swift` 的 `PriorityCapsule`）。**Doing** 是 Perch 自己的状态（Reminders 没有进行中，EventKit 读写不了旗标 / 标签），什么都不写进提醒、手机上看不到：`todo_refs` 上的布尔 `doing`（schema v7），所以跟着短 id 走——在勾选列表之间挪（#70）、取消勾选再勾上都还在；`status` 仍是 `open`，item 的 JSON 带 `doing`（每条 todo 都带，别的 item 没有）。`perch update <id> --doing` / `--no-doing`（patch 的 `doing`）直接在 perchd 里改、不经 bridge，所以 App 没连着也行；只对 open 的 todo（做完的、非 todo 报错），而且要单独一次 update（和别的字段一起给就报错）。快照里那条提醒完成了（包括在 tab 里完成）、或者它的列表还勾着它却不在了（删了、在 Reminders 里挪到没勾的列表）就清掉（`Service.applySnapshot`，按快照的 `todo_lists` 判断勾没勾）；列表被取消勾选时留着；重新打开不会回来。排序：`Item.todoOrder`（`TodoList`、`perch ls`、`todo.md` 共用）是 Doing、再优先级、再创建时间、再 id；`perch ls` 在行尾标 `· doing`，`todo.md` 详情第一项是 `doing`。行上的 ▶：不是 Doing 的行只在指针在行上时出现、灰色（`HoverTracker`：刘海面板从不是 key，所以用 `.activeAlways` 的 tracking area，不靠 SwiftUI 的 hover）；Doing 的行一直显示、白色实心（11pt），它就是标记，整行还有一层浅底（约 8% 白，刚加的那一秒的高亮仍是 14%）、标题加粗，远看也认得出；点了是 `QueueModel.toggleDoing`（经 perchd）。不在右键菜单和编辑器里；可以同时任意多条；算未完成（摘要、tab 栏、收起态的数照算），摘要不提 Doing，收起态不变。

**2026-10-12（v0.5，#31 / M11）**：接入 Grok Build（xAI 的 `grok` CLI），v0.5 接更多 agent（#24）的第一个。刘海永远不能批准 Grok，只提示"Answer in the terminal"。

**2026-10-19（v0.5，#73 / M15）**：接入 dsh（DeepSeek Harness，Node 写的 agent 框架），显示名 "DeepSeek"、鲸鱼图标。dsh 只能从里面扩展，所以 Perch 带一个 dsh 插件（`packaging/dsh/perch.mjs`），它只把 dsh 的事件搬给 `perch hook dsh`，状态全在 Swift 里判（#74 / #75）。只支持终端 UI（`dsh web` / `dsh headless` 不支持），刘海永远不能批准 dsh。安装（#76）：插件嵌在 perch 里、写在 perch 二进制旁边（`~/.perch/bin/perch-dsh.mjs`），dsh 的 home patch 层 `$DSH_HOME/cordis.patch.yml`（所有 profile 都读）里一段带标记的 insert 行把它挂上。细节见下面"Hook 适配"里的 dsh 一节。

## 仓库结构

```
Package.swift            SwiftPM：PerchCore（库）、perch（CLI）、perchd（daemon）、PerchApp（刘海 App）
Sources/PerchCore/       模型、wire protocol、路径、纯解析/渲染。所有客户端共享，不含任何 I/O
Sources/PerchClient/     Unix socket 客户端（CLI 和刘海 App 共用）；sysctl 读进程（hook 找 agent、perchd 存活检测）
Sources/PerchAppCore/    刘海 App 的可测逻辑（库，不含 AppKit）：几何、队列状态、提醒、快捷键解析、连接 perchd、自检和设置行（`Setup` / `AppSetup` / `SetupModel`）、开机启动（`LoginItem`）、tab 和 Todo tab（`PanelTab` / `TodoList` / `TodoEditor`）、Reminders 接缝、bridge 和列表选择（`RemindersStore` / `RemindersBridge` / `ListSelection`）
Sources/PerchDaemon/     daemon 的全部逻辑（库，便于测试）：SQLite、请求处理、socket/HTTP、文件镜像
Sources/PerchSetup/      安装 Perch（库，有 I/O）：agent hook 文件读写、perchd 的 launchd agent、agents.json、固定安装位置、状态评估（纯函数 `Setup.evaluate`）、卸载；CLI / perchd / 刘海 App 共用
Tests/PerchSetupTests/   状态评估的纯函数测试；`perch setup` / `uninstall` 的端到端测试在 PerchDaemonTests/SetupCLITests（临时 HOME + 假 launchctl）
Sources/CSQLite/         系统 libsqlite3 的最小声明（见下方 SQLite 决定）
Sources/perch/           CLI，唯一对外契约（ArgumentParser）
Sources/perchd/          daemon 可执行文件入口，只做组装
Tests/PerchCoreTests/    swift-testing（`import Testing`；只装 Command Line Tools 也能跑，XCTest 需要完整 Xcode）
Sources/PerchApp/        刘海 App（AppKit + SwiftUI），SwiftPM 可执行 target，不需要 Xcode
packaging/Info.plist     Perch.app 的 Info.plist（LSUIElement，无 Dock 图标）
packaging/Perch.icns     App 图标（橙色像素独眼怪吊在刘海下面，2026-10-10 起；之前是像素小鸟）；改图在 scripts/icon/draw-icon.swift，scripts/icon/make-icon.sh 重新生成并提交 .icns
packaging/sounds/        提示音（#35）：needs-you / failed / done.wav，scripts/sound/make-sounds.swift 合成（小怪物的声音），scripts/sound/make-sounds.sh 重新生成并提交；bundle-app.sh 拷到 Contents/Resources/Sounds
packaging/dsh/perch.mjs  dsh 插件（#75，唯一的 JS 文件）；改完跑 scripts/dsh/embed-plugin.sh，把它嵌进 PerchSetup（`DshPlugin.source`）一起提交
scripts/bundle-app.sh    编译 PerchApp 并组装、ad-hoc 签名成 .build/Perch.app；perch / perchd 放在 Contents/Helpers（App 自检从这里同步到 ~/.perch/bin），Contents/Resources/bin/perch 是 packaging/perch-path.sh
packaging/perch-path.sh  Homebrew 链到 PATH 上的 `perch`：转去执行 ~/.perch/bin/perch，还没有时提示先打开一次 App
Casks/perch.rb           Homebrew cask，tap 就是本仓库（`brew tap cryptowizard0/perch https://github.com/cryptowizard0/perch`）
scripts/package-release.sh  发版打包：只含 Perch.app 的 dist/perch-<v>-macos-arm64.zip + .sha256，并改 Casks/perch.rb 的 version / sha256
docs/                    PRD、里程碑、给其他 agent 用的 SKILL 片段、发版说明模板（RELEASE-NOTES-TEMPLATE.md）
Sources/perch/Hook*.swift  hook 适配器就是 CLI 子命令：`perch hook <agent>`（读 stdin）、`perch hooks install|uninstall`
scripts/install.sh       从源码安装：打包 Perch.app → ~/Applications（或 /Applications，别处直接报错）并打开（首次运行走设置卡片）；已经装过（~/.perch/bin 或 v0.3 的 ~/.local/bin）时再跑 App 自带的 `perch setup --upgrade`；~/.local/bin 放链接
```

## 常用命令

```
swift build                      # 编译 CLI + daemon + 库
swift test                       # 单元测试，每次提交前必须通过
swift run perch --help
swift run perchd                 # 前台跑 daemon（PERCH_HOME=/tmp/x 可隔离数据）
swift run perchd install         # 装成 launchd agent（--dry-run 只打印 plist）；perchd uninstall 移除
perch setup [agent…] [--json]    # 安装到 ~/.perch/bin + launchd + 连接 agent
perch setup --upgrade            # 拷二进制、重启 perchd、修已连接 agent 的 hook，不连新的（scripts/install.sh 升级时跑 App 里的这份）
scripts/install.sh               # 从源码安装 / 升级（见上）
scripts/package-release.sh       # 发版打包（在 tag 的 worktree 里跑）
perch uninstall [--purge]        # 卸掉 hooks、launchd、~/.perch/bin；--purge 连 ~/.perch 一起删
scripts/bundle-app.sh            # 打包刘海 App → .build/Perch.app（CONFIG=debug 出调试版）
open .build/Perch.app
scripts/measure-latency.sh       # M2 验收：隔离的 perchd + App，量 CLI → 刘海延迟
```

## 不可动摇的架构决定

1. **daemon 是唯一真相。** 只有 `perchd` 打开 SQLite。CLI、刘海 App、Hermes 全是客户端，谁都不直接碰数据库。例外是 todo（#51）：它的真相是 Reminders 的 "Perch" 列表（#69 起加上勾选的其他列表），perchd 只存可重建的缓存，只有 bridge App 写 Reminders。
2. **CLI 是唯一契约。** 任何能跑 shell 的 agent 零学习成本接入；存储格式可以随时换，CLI 参数不能随便改。全部子命令支持 `--json`；`add --key` 幂等。
3. **推事件，不轮询。** daemon 通过 socket 广播 `Event`，刘海 UI 订阅。CLI 调用到刘海更新 ≤ 200 ms。
4. **传输层。** Unix socket `~/.perch/perchd.sock`（本机），加 `127.0.0.1:7331` HTTP（给跑在容器里、够不着 socket 的客户端，`host.docker.internal:7331`；本机的 Hermes 走 hook，见下）。两者跑同一套 JSON（`Sources/PerchCore/Protocol.swift`）：socket 上是 newline-delimited JSON，HTTP 上是 `POST /rpc`；`watch` 保持连接并逐行推送带 `event` 的 `Response`。
5. **文件是单向的。** `~/.perch/todo.md` 是 daemon 渲染的只读镜像；`~/.perch/inbox.md` 是追加式收件箱，daemon 监听到 `- [ ] …` 就经 bridge 写进 Reminders、再从文件里删掉那一行（#52；没有 bridge 时留在文件里）。**没有双向同步，永远不要实现。** Reminders（#51）也不是双向同步：只有一个真相（"Perch" 和勾选的其他列表，#69），SQLite 里只是它最近一次快照的只读缓存加短 id 引用，丢了能重建，缓存只由快照写。
6. **刘海只是快捷通道，不是唯一通道。** hook 等刘海响应 15–30 秒，超时不返回决定，终端原生提示照常弹出。任何情况下都不会因为 Perch 而默认放行。
7. **一种语言。** 全部 Swift 5.9 / macOS 14+。daemon 和 CLI 打成单二进制。唯一的例外（#73 定）：dsh 只能从里面扩展，所以有一个不依赖任何包的 `packaging/dsh/perch.mjs`，只搬运事件、不做任何判断；它嵌在 perch 里（`scripts/dsh/embed-plugin.sh` 生成 `Sources/PerchSetup/DshPluginSource.swift`，`DshPatchTests` 保证两者一字不差）。

## 数据模型

一张 `items` 表，字段与 `Item`（`Sources/PerchCore/Models.swift`）一一对应，JSON 用 snake_case，日期 ISO-8601：
`id`（4 位可手打，如 `t7k2`）、`title`、`kind`（task / notice / request）、`status`（open / waiting / done / dismissed）、`priority`（high / normal / low，默认 normal；schema v4，#42）、`source`（自由字符串）、`due_at`（刘海不再用，只为兼容留着）、`link`、`meta`、`key`、request 专用的 `options` / `response` / `expires_at`、`created_at` / `updated_at`。
todo（#51，schema v5）：open / done 的 task 是 "Perch" 和勾选的其他 Reminders 列表（#69）的缓存，只有 bridge 的 `todo_snapshot` 写（CLI 的写经 bridge 绕一圈回来，#52）；`due_date_only`（schema v6，#52）表示 `due_at` 是一整天；`todo_refs`（`id` ↔ `external_id`（`calendarItemExternalIdentifier`）↔ `key`，加 `doing`（schema v7，#71：Perch 自己的"正在做"，默认 false））给它们短 id，引用从不删（提醒回来短 id 不变，Doing 也跟着）。缓存的 item：source `reminders`、`meta.reminder` 是外部标识符、`meta.list_id` / `meta.list_name` 是所在列表的 `calendarIdentifier` 和名字（#69；JSON 里另有只出不进的 `list` = 列表名，给 `perch ls --json`）、`meta.notes` 是备注（#53，有才写）；`doing`（#71）从 `todo_refs` 读出来，JSON 里每条 todo 都带；勾选列表的顺序和描述（id、名字、iCloud）存在 `daemon_state` 的 `todo_lists`（JSON，#69，不改 schema）；字段对应：优先级 1–4 → high、0 / 5 → normal、6–9 → low（写 1 / 0 / 9），完成 → done，到期 → `due_at`，URL → link，创建时间 → `created_at`。等待中的 task、notice、request 仍是 perchd 自己的。
`kind` 区分 task 和 notice 是刻意的："agent 完成了"不是待办，混在一起会稀释橙色信号。
优先级（#42）：`perch add|update --priority high|normal|low`（`-p`），值不对是用法错误（exit 64）；JSON 里缺省就是 normal（HTTP 客户端照旧）；`update` 的 patch 可以改它，同 `key` 重新 add 也会改。`queueOrdered`（`perch ls`、`todo.md`）把 open 的 task 排在一起：#69 起先按列表（勾选顺序），再按 Doing（#71），再按 High / Normal / Low，再按创建时间（到期日期不再排序）；`ls` 和 `todo.md` 标出 High / Low 和 doing。inbox 没有优先级语法。schema v4 是 `ALTER TABLE items ADD COLUMN priority … DEFAULT 'normal'`，老数据都是 Normal。

M7 起有 `sessions` 表（schema v2，字段与 `Session`（`Sources/PerchCore/Sessions.swift`）一一对应）：会话状态只放这里，重启后原样恢复。hook 适配器发 `session_report`（`SessionReport`：prompt / waiting / resume / stop / failure / interrupt / end，与 agent 无关），状态机在 perchd 的 `SessionRegistry`：比该会话最后一次事件旧的报告丢弃（平局照收），被移除的会话 10 分钟内记着移除时间，旧事件不会让它复活；Done 10 分钟后变 Idle（`session_seen` 立刻变）；resume / stop / failure / interrupt / end 顺带把 `meta.session_id` 指向该会话的 request 关掉（不带回应）。白名单内的 PermissionRequest 仍发 request（经 `meta.session_id` 挂到会话）。报告可以带 `turn_id`（Grok 的 `promptId`）：prompt 把它记成会话的当前轮，别的轮的 stop / failure / interrupt 直接丢掉（Grok 的取消报告可能晚于下一轮的 prompt 才到）；当前轮只存在 `SessionRegistry` 内存里，perchd 重启后退回按时间判断，不动 schema。`settle`（Grok 的 `idle_prompt`）只把 Running / Needs you 改成 Idle，Done / Failed 不动，也不新建会话。M8（#19）起 Claude Code / Codex 的 hook 不再发 waiting / notice item，request 是它们唯一会建的 item。清理：pid 存活检测（30 秒，比对进程启动时间防复用）为主，拿不到 pid 的 24 小时无事件兜底，`perch session rm` 手动移除（#16）。`perch hook` 沿父进程链找 argv[0] 叫 `claude` / `codex` 的最近祖先（`AgentProcess`，纯函数；进程表由 `PerchClient/SystemProcesses.swift` 用 sysctl 读），每条 `session_report` 带上它的 pid 和启动时间。**按 argv[0] 认，不按内核进程名**：`~/.local/bin/claude` 是指向 `versions/2.1.x` 的符号链接，内核记的名字是 `2.1.x`。

## Hook 适配（M3 / M4 / M5）

两家的 stdin JSON 结构、返回格式和 600 秒默认超时一致，共用一个适配器：`perch hook <agent>`（Swift，不写 shell 脚本；映射逻辑在 `PerchCore/Hooks.swift` 的 `HookAdapter`）。事件集合不同（M5 核对）：Codex 没有 `Notification` / `StopFailure` / `PostToolUseFailure`（waiting 只来自 PermissionRequest），多一个 `Interrupt`（Esc 打断一轮，不会再有 Stop）；`SessionEnd` 在 Codex 里总是同步跑、最多 3 秒。`perch hooks install <agent>` 按各家的事件表写。
不阻塞的 hook 一律 `"async": true`（例外：Codex 的 `SessionEnd` 总是同步跑，装成同步、timeout 3；Codex 的 `Interrupt` 即使 async 也最多 3 秒）；适配器**不往 stdout 打任何东西**（SessionStart / UserPromptSubmit 的 stdout 会进模型上下文）、永远 exit 0，失败写 `~/.perch/hook.log`。

每个事件只发一条 `session_report` 更新会话状态（映射见 `HookAdapter` 的文档注释和 `docs/PRD.md`"Agent 面板"），会话是唯一的状态；唯一的 item 是白名单内 PermissionRequest 的 request。阻塞、不打 stdout、exit 0、超时交给终端这些规则不变。PermissionRequest 的 request 没有回应就结束（过期、被 done / rm、被会话事件关掉）一律把会话改成"完整命令 + Answer in the terminal"，因为没有决定就是终端在问。

| 事件 | 会话 | 阻塞 agent |
| --- | --- | --- |
| `UserPromptSubmit` | running（本轮 prompt 首行）；Ghostty 下记下当前聚焦的 terminal id。Claude Code 自己注入的 `<task-notification>`（后台任务跑完）也触发它：报告带 `keep_prompt`，保留人上一条 prompt，会话还在 Running / Needs you 时计时也不重置，不重新记 terminal（#32） | 否 |
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

Grok Build（M11，#31；按 grok 1.0.50 实测，2026-10-12）：同一个适配器 `perch hook grok`，事件名和 Claude Code 一样，payload 是 camelCase（`sessionId`、`lastAssistantMessage`、`promptId`），只有部分 key 有 snake_case 副本（`session_id`、`hook_event_name`、`tool_name`、`tool_input`、`transcript_path`），所以 `HookInput` 每个字段两种名字都认。Grok **没有 async**（写了会记一条加载错误），所有 hook 前台跑、默认超时 5 秒（Stop / PostToolUse 默认 600 秒），所以每个 hook 都写明短超时；`perch hook grok` 实测约 7 ms。**Grok 没有 PermissionRequest，PreToolUse 的 `allow` 只是"不拦"、不会跳过提示框**，所以不建 request、刘海永远不能批准 Grok。不装 PreToolUse（`permission_prompt` 的原话只有 "Tool permission requested"，没有命令；要显示完整命令就得每次调工具都前台跑一次 perch，以后再说）。

| 事件 | 会话 |
| --- | --- |
| `UserPromptSubmit` | running（prompt 首行），`promptId` 记成当前轮；Ghostty 下记下聚焦的 terminal |
| `Notification` `permission_prompt`（和工具调用同时发，不像 Claude Code 要等 6 秒） | waiting："Tool permission requested" + "Answer in the terminal" |
| `Notification` `idle_prompt`（一轮结束约 1 分钟后） | settle：兜底那些不发结束事件的轮（实测：模型还没开始就按 Ctrl+C，什么都不发） |
| `PostToolUse` / `PostToolUseFailure` | running |
| `Stop`，`reason == "end_turn"` | done（`lastAssistantMessage` 首行）；会话结束时多发的那次（`shutdown` / `channel_closed`）丢掉 |
| `StopFailure` | failed（`error`） |
| `StopCancelled` | `cancelledBy: user`（Ctrl+C、拒绝或关掉提示框）→ idle；`runtime`（`max_turns`、`no_progress`）→ failed |
| `SessionEnd`（关终端也会发） | 移除 |

带 `subagentType` 的事件（子 agent 自己的会话）一律忽略。进程：hook 的父进程就是 `grok`（`~/.grok/bin/grok` 和 `agent` 都是指向带版本号二进制的链接，按 argv[0] 认这两个名字）；开了 leader 模式（`[cli] use_leader`，默认关）时会话共用 leader 进程，只能等 `SessionEnd` 或退出 leader 才清掉。**Grok 默认也跑 `~/.claude/settings.json` 里的 hook**（`[compat.claude] hooks`），payload 带 `session_id` / `hook_event_name` 能解出来，所以除了 `grok` 以外的适配器看到 `GROK_HOOK_EVENT` 就直接退出（`HookAdapter.isForeign`），不然会多出一条没有 pid 的 claude-code 会话。Grok Bot.app（桌面 App）不在范围内。

dsh（DeepSeek Harness，#73 / #74，按 dsh 0.2.0-rc.2 + dsh-tui 0.14.0 实测，2026-10-19）：dsh 是 Node 写的、只能从里面扩展，所以 Perch 自己带一个 dsh 插件（#75），它看 dsh 自己的事件，每个状态变化 spawn 一次 `perch hook dsh`、stdin 一个**已经规整好**的 JSON（不等它结束），状态怎么判全在 Swift（`HookAdapter.dsh`）。payload：`hook_event_name`、`session_id`、`cwd`、`at`（dsh 的事件时间，epoch 毫秒，就是报告的 `at`：一个事件一个 perch，到达可能乱序，perchd 丢掉比会话最后一次事件旧的）、`pid`、`turn`（像 Grok 的 `promptId`：别的轮的 TurnEnd 丢掉；字符串或数字都认）。标题照旧是 `cwd` 的项目名（不用 dsh 自己的 `session/title`）。**刘海永远不能批准 dsh**：不建 request、`perch hook dsh` 不走 PermissionRequest，Needs you 永远写 "Answer in the terminal"（dsh 几乎只为沙箱升级 `danger-full-access` 提问，本来就在白名单外）。

| 事件 | 会话 |
| --- | --- |
| `Prompt`（`prompt`；`keep_prompt`：不是人起的轮——goal driver、schedule、后台任务） | running（prompt 首行），`turn` 记成当前轮；Ghostty 下记下聚焦的 terminal（`keep_prompt` 的不记、保留人上一条 prompt） |
| `ApprovalAsked`（`tool_name`、`tool_input`（对象或 JSON 字符串）、`reason`） | waiting：完整命令（`bash` 是 `command` 本身，别的工具是名字 + 所有参数）+ "Answer in the terminal: <reason>" |
| `QuestionAsked`（`questions` 的 `question` / `header`） | waiting：第一个问题（+ "(and N more)"）+ "Answer in the terminal" |
| `Answered`（批准、拒绝、Esc / Ctrl+C、回答或取消问题） | resume → running |
| `TurnEnd` `reason`：`completed` / `max-tokens` / 其他 | done（`last_assistant_message` 首行） |
| `TurnEnd` `error` | failed（`error`：字符串，或对象的 `message`） |
| `TurnEnd` `aborted`（Esc）/ `blocked`（hook 拦了 prompt） | interrupt → idle |
| `SessionEnd`（`session/disposed`、插件 dispose 时给所有还活着的会话） | 移除 |

进程：dsh 跑成 `node …/bin/dsh <profile>`，argv[0] 规则认不出来。插件直接（不经 shell）spawn perch 并传 `process.pid`，所以 payload 的 `pid` **只有是 `perch hook dsh` 的父进程时才信**（`AgentProcess.dsh(claimed:parent:)`），启动时间从 `SystemProcesses` 拿，pid 存活检测和防复用照旧；不是父进程就不带 pid（24 小时兜底）。关终端（SIGHUP）时 dsh 什么都不发，靠 pid 存活检测（30 秒）清掉。dsh 自带的 Claude Code / Codex hooks bridge（`dsh-hooks-claude-code` / `dsh-hooks-codex`，默认不挂）会跑 `~/.claude/settings.json` / `~/.codex/hooks.json`，而且不给 hook 进程设任何能认的环境变量（`DSH_*` 会被它的执行器清掉），所以 `perch hook claude-code` / `codex` 沿父进程链往上走，先碰到 dsh 进程（`node` 且 argv[1] 是 `…/dsh` 或 `@deepseek-ai/dsh/` 下的脚本，或者叫 `dsh` 的二进制；`SystemProcesses` 现在也读 argv[1]，`ProcessEntry.script`）、再碰到自己的 agent 进程就直接退出（`AgentProcess.insideDsh`，`HookAdapter.isForeign`）；dsh 的 bash 里起的 `claude` 照样是 Claude Code。`dsh web` / `dsh headless` 不支持（插件不动，#75）；插件、安装和图标是 #75 / #76。

安装（#76）：dsh 的 profile 由一层层 patch 叠出来，home 层 `$DSH_HOME/cordis.patch.yml`（`DSH_HOME` 默认 `~/.dsh`）对**所有** profile 生效（以后新建的也算），所以 Perch 只往那里写一段带标记的 insert 行（`DshPatch`，`# >>> perch: …` 到 `# <<< perch <<<`），`name` 是插件的绝对路径、`config.perch` 是 perch 的绝对路径，都用 YAML 单引号。插件嵌在 perch 里（`DshPlugin.source`），作为 hook 的"附带文件"（`HookFile.supportFiles`）写在 perch 二进制旁边（`~/.perch/bin/perch-dsh.mjs`）：先写插件再写那一行；每次同步二进制时只要 dsh 是 on 就重写一遍（`Installer.refreshSupportFiles`），所以插件永远和 perch 同版本；`perch uninstall` 删 `~/.perch/bin` 时它跟着没了。没有 YAML 库，按文本处理（和 Hermes 一样）：只往块状列表（`- …` 行）、空文件、只有注释或只有 `[]` 的文件里加，别的形状（flow 风格、映射）一律报错、不动；改之前写 `.perch-backup`；删掉那一段后只剩空行和注释就删掉文件（`HookFile.isBlank`）。dsh 遇到 `name` 指向不存在的文件照样能启动（实测），所以插件没了也不会弄坏 dsh。检测按 dsh 的 home 目录（`$DSH_HOME` 或 `~/.dsh` 存在）；不需要信任；装完要重开 dsh 会话。

会话 CLI：`perch session ls [--json]`（状态和详情）、`perch session seen <id>`（done → idle）、`perch session rm <id>`（手动移除，之后再来事件会重新出现）；`perch session start|end` 保持旧含义（start = 新一轮 running，end = 移除），Hermes 还在用。`watch` 推 `session.updated`（每次变化）、`session.ended`（移除）和 `session.started`（新一轮开始，给老客户端）。刘海（M8，#18）只显示会话（Hermes 除外：2026-10-08 起暂不支持，M9 搁置）：收起态 = 最紧急会话的状态（像素独眼小怪物，按状态换表情和动作，#22；帧逻辑在 `PerchAppCore/Mascot.swift`，绘制在 `PerchApp/MascotView.swift`）+ Running 数；展开态按状态分组，逻辑在 `PerchAppCore/Panel.swift`（`Panel` / `SessionRow`），像素图标在 `PixelIcon.swift`。Live Activity（"2 agents · 4m"）已去掉。

`perch add --kind request --wait` 的约定：有人回应 → stdout 打印回应值、exit 0；过期（`--expires`）/ 被 done / 被 rm → exit 3、不打印回应。适配器只在 exit 0 时返回决定，其余一律不返回，让终端原生提示接管。

返回格式（M4 按官方文档核对过）：Claude Code 是 `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"|"deny","message":"…"}}}`（`message` 只用于 deny；不是 PreToolUse 的 `permissionDecision`；exit code 2 在 PermissionRequest 不生效）。Codex（M5 核对）读同一个 JSON，所以不分支；不要返回 `updatedInput` / `updatedPermissions` / `interrupt`（Codex 目前对这些 fail closed）。
PermissionRequest 在弹提示框**之前**触发；`Notification` 的 `permission_prompt` 要等提示框挂了约 6 秒才触发。
**Claude Code 在权限提示上选 No 或按 Esc 时不发任何 hook**（#8 实测，2.1.258：`idle_prompt` 也不来），只在 transcript 里写 `[Request interrupted by user for tool use]` + `system/turn_duration`。所以 Claude Code 的报告带 `transcript_path`（存在会话里，schema v3），perchd 监视 Running / Needs you 会话的 transcript（`TranscriptWatcher`），末尾的消息是这个标记（`ClaudeTranscript.interruption`）就按标记时间发 `interrupt` → Idle。transcript 不是公开接口，格式变了就退回原样（会话停在原状态）。思考中、还没输出就按 Esc 时 transcript 什么都不写，会话停在 Running，直到下一条 prompt 或关 tab（已知限制）。
配置文件：Claude Code `~/.claude/settings.json`；Grok `~/.grok/hooks/perch.json`（`$GROK_HOME` 可覆盖；Perch 独占的文件，`~/.grok/hooks/*.json` 里的全局 hook 不需要信任，Grok 在会话开始时加载，所以装完要重开 grok 或在 `/hooks` 里按 r）；Codex `~/.codex/hooks.json`（`$CODEX_HOME` 可覆盖；Codex 按 hook 内容的 hash 记信任，新装或改过的 hook 要在 codex 里 `/hooks` 确认后才会跑）；Hermes `~/.hermes/config.yaml` 的 `hooks:`（`$HERMES_HOME` 可覆盖；没有 YAML 库，Perch 在文件末尾写一段带标记的块；Hermes 用 yaml.dump 重写文件时标记会丢，所以只含 Perch 命令的 `hooks:` 段也认作 Perch 的；混了别人 hook 的 `hooks:` 段不动、安装拒绝；Hermes 对每个 (事件, 命令) 首次运行要确认，记在 `~/.hermes/shell-hooks-allowlist.json`，gateway 要 `hermes gateway restart` 才会加载）。
以官方文档为准：https://code.claude.com/docs/en/hooks 、 https://learn.chatgpt.com/docs/hooks 、grok 自带的 `~/.grok/docs/user-guide/10-hooks.md`、Hermes 仓库的 `website/docs/user-guide/features/hooks.md`（Shell Hooks 一节）。

## 安装（#26，零配置安装的第 1 步）

- **固定安装位置 `~/.perch/bin/{perch,perchd}`**：真拷贝（不是链接）、去掉隔离标记、原子替换。hook 命令和 launchd plist 永远指向这里，所以升级、挪 App / checkout 都不改 hook 文本，Codex 的信任不丢。`~/.local/bin` 里的只是给人敲的链接，永远不写进 hook。
- **`~/.perch/agents.json`**：每个 agent 记 `status`（on / off）、实际写过的 `config` 路径、`hooks_written_at`（Perch 的 hook 内容变了才更新）、Codex 的 `trusted_at`（下一步由 App 在看到 Codex 事件后写）。没有条目 = 没问过；但没有条目却有 Perch 的 hook（v0.3 装的）算 on。文件坏了就报错、不覆盖。
- **检测按配置目录**：依次看 agents.json 里记的路径、`$CLAUDE_CONFIG_DIR` / `$CODEX_HOME` / `$GROK_HOME` / `$DSH_HOME`、默认目录，取第一个 agent 目录存在的（`ConfigLocation.agentDirectory`：hook 文件路径去掉 `file` 那几级，Grok 是 `~/.grok`，因为 `~/.grok/hooks` 默认不存在）。不看 PATH 上有没有可执行文件。Perch 独占的 hook 文件（`HookFile.ownsFile`，目前只有 Grok 的）不写 `.perch-backup`（会躺在 Grok 的 hooks 目录里），Perch 的 hook 都删掉后文件也删掉（里面有别人的 hook 就留着）。Hermes 不参与检测和连接（手动 `perch hooks install hermes` 照旧）；`perch uninstall` 会顺带删 Hermes 里 Perch 的 hook。
- **状态评估是纯函数** `Setup.evaluate(snapshot, request:)`：输入 agents.json、各候选配置文件内容、已装 / 自带版本、谁在跑（CLI / App 路径）、环境变量；输出每个 agent 的状态（notDetected / notAsked / connected / outdated / needsTrust / off，外加 error）和计划（同步二进制、要写的 hook）。`perch setup` 和以后 App 的自检都按这个计划做。比较的是 Perch 自己那几条 hook 的规范形式（`HookFile.perchHooks`），别人的 hook、key 顺序、格式都不影响判断。
- **自修复**：on 的 agent 的 Perch hook 路径或内容不对就重写，保留原来的 `--wait`；只碰 Perch 的 hook；JSON 坏了原样不动、报错；每次改之前写 `.perch-backup`。`perch setup` 显式给 `--wait` 时以它为准。
- **二进制同步**：`perch setup` 总是拷贝（开发构建版本号相同，不能按版本判断）；App（下一步）只在装在 /Applications 或 ~/Applications、且没设 `PERCH_HOME` 时、版本不同（两个方向）才同步，否则什么都不碰。
- `perch hooks install|uninstall` 记 on / off；install 默认让 hook 跑 `~/.perch/bin/perch`（不存在时警告）。`hooks uninstall` 之后 `perch setup` 不会再连这个 agent，除非点名。
- **App 自检与设置 UI（#27）**：只有装在 /Applications 或 ~/Applications、没设 `PERCH_HOME` 的 App 才做（`Setup.maintainsInstall`），`.build/Perch.app` 和隔离运行既不同步也不显示任何设置 UI（卡片、设置行、Agents 子菜单都没有）。每次启动：版本不同就从 `Contents/Helpers` 同步二进制并重启 perchd；修 on 的 agent 的过期 hook。首次运行（卡片没显示过、agents.json 为空）刘海自己展开一次显示设置卡片，Connect 之前不改任何 agent 的配置。设置行在会话分组之上（`Panel.sections`），逻辑在 `PerchAppCore/Setup.swift` 的 `SetupState`，`PerchApp` 只画。Codex 信任：App 看到 codex 的 `session.updated` 且 `updated_at` 晚于 `hooks_written_at` 就写 `trusted_at`，perchd 不变。App 连的 perchd 是 `SetupEnvironment.current.socket`。
- **开机启动与卸载（#28）**：App 用 `SMAppService.mainApp` 注册自己（`PerchAppCore/LoginItem.swift`，不走 launchd）。首次运行卡片多一个 "Open at login" 勾选框（默认勾上），Connect 时连同 agent 一起生效；Not now / OK 也照它办（这个框管的是 App，不是 agent）。右键刘海的 "Open at Login" 显示当前注册状态（`SetupState.loginMenu`：enabled 打勾、点了注销；没注册点了注册；在系统设置里被关掉（requiresApproval）时点了打开 系统设置 → 登录项，只有用户能在那里放行）。"Uninstall Perch…" 先弹确认，然后 `AppSetup.uninstall`：和 `perch uninstall` 同一个 `Installer.uninstall(purge: false)`（保留 `~/.perch` 数据）→ 注销登录项 → App 移到废纸篓 → 退出；清不掉的 hook 文件不挡后面的步骤（和 CLI 一样，弹窗说明），再往后的失败（launchd / `~/.perch/bin` 删不掉）就停下、App 留着。两者都只在 `Setup.maintainsInstall` 的 App 里出现。登录项属于真实登录的用户、不看 `$HOME`，所以 `$HOME` 不是真实 home（隔离运行）时没有登录项（`LoginItem.mainApp(forHome:)` 返回 nil）：卡片不显示勾选框、菜单没有 Open at Login、卸载跳过注销。卸载进行中（`SetupModel.uninstalling`）Connect / 断开 / 开关登录项 / 刷新都不做，菜单只剩 Quit。测试注入假的 `LoginItem` 和 trash，永远不注册测试进程。
- **分发（#29）**：用户的安装路径是"拖进 Applications（或 `brew install --cask cryptowizard0/perch/perch`）→ 打开、过 Gatekeeper → 卡片 Connect → Codex 里 `/hooks` 一次"，二进制、launchd、hook 都由 App 做，cask 和 zip 不碰任何 agent 配置。**Homebrew**：homebrew/cask 从 2026-09-01 起停用过不了 Gatekeeper 的 cask、删了 `--no-quarantine`；但 Gatekeeper 检查只在 `brew audit`（官方仓库的 CI）里，安装时不查，所以自建 tap 能装，只是一定带隔离标记。tap 就是本仓库（`Casks/perch.rb`，2026-10-12 用户定，不单独建 homebrew-perch）。**brew 7 默认要求信任第三方 tap**（`HOMEBREW_REQUIRE_TAP_TRUST` 默认开，信任记在 `~/.homebrew/trust.json`）：短名字 `brew install --cask perch` 会被拒绝（"Refusing to load cask … from untrusted tap"，本地 tap 实测），`install` / `upgrade` / `reinstall` 用完整名字 `cryptowizard0/perch/perch` 时会自动信任这一个 cask，所以文档里一律写完整名字。**隔离标记的坑（实测）**：带标记的 ad-hoc 二进制在 shell 里一执行就被内核 SIGKILL（exit 137）；用户批准（Open Anyway）之前，bundle 里的任何可执行文件都会被杀，哪怕文件本身没有标记，因为 Gatekeeper 评估的是整个 bundle；bundle 外带标记的 shell 脚本能跑；批准之后 bundle 里的包装脚本能跑（2026-10-12 用真实的 v0.4.0 cask 验证）。所以 cask 的 `binary` 链的是 App 里的包装脚本（`packaging/perch-path.sh`），它转去执行 App 首次打开时装好、已去掉标记的 `~/.perch/bin/perch`，CLI 和 hook 永远是同一份；uninstall 用 `/bin/sh -c` 跑 `~/.perch/bin/perch uninstall`（没有就跳过：没打开过就什么都没装），所以不依赖 bundle；**brew 在 upgrade / reinstall 时也跑 uninstall 的 `script`**（brew 7 只跳过 `signal`），那样会断开所有 agent，所以脚本看父进程（brew 本身）的命令行，含 ` upgrade` / ` reinstall` 就跳过（本地 tap 实测：upgrade / reinstall 不调、uninstall 调）；zap 只 trash `~/.perch` 和偏好设置（uninstall 已经先跑过）。cask 的 `quit: "dev.perch.app"` 会退出正在跑的 Perch（测试 cask 时注意）。发版 zip 只含 Perch.app（v0.3 及以前还有 perch / perchd）。App 自检每次启动也把 v0.3 留在 `~/.local/bin` 的旧二进制换成链接（`Installer.linkOldBinaries`，和 `perch setup` 一样），所以 v0.3 换 App 就能升级。`perch setup --upgrade`（`SetupRequest.upgrade`）= 自检那套（修已连接 agent 的 hook、不连新的、不放回 `perch uninstall` 删掉的）但总是拷二进制，给 `install.sh` 升级用，这样它不会连上卡片里 Not now 的 agent。
- 测试接缝：setup 的路径都从环境变量来（`HOME`、`PERCH_HOME`、`CLAUDE_CONFIG_DIR`、`CODEX_HOME`），`PERCH_LAUNCHCTL` 可以换掉 `/bin/launchctl`（测试里是只记参数的脚本）。测试永远不碰真的 `~/.claude` / `~/.codex` / `~/.perch` / launchd。

## 安全规则（M4 必须实现，不可绕过）

- 展开态必须显示完整命令原文，不截断不摘要。
- 白名单之外的工具不给批准按钮，只显示"去终端"。默认白名单：Read / Glob / Grep / WebFetch / WebSearch；Bash 只放 `npm test`、`pytest`、`cargo test`、`git status|diff|log`。`rm`、`sudo`、`git push --force`、`curl | sh`、写 `.env` / `~/.ssh` / `*.pem` 一律去终端。
- 白名单是本地配置文件，用户可改；默认值宁严勿松。已实现（M4）：`~/.perch/allowlist.json`（没有文件 = 默认值；文件坏了 = 什么都不能在刘海批准），`perch allowlist [show|check|init]`。Bash 带 shell 元字符（`; & | $ \` > < ( ) \` 换行）或危险参数（`--output` 等）一律去终端；受保护路径对所有工具生效。
- 白名单外的请求不会变成 request：hook 立刻返回（终端马上弹提示框），刘海里那个会话只显示完整命令和"Answer in the terminal"。刘海按钮只对 request 显示，所以不存在"白名单外却有 Allow 按钮"的路径。

## 范围守卫（不要做）

dispatch（从刘海派任务给 agent）、stop / cancel、reply（在刘海里回答 agent 提问）、MCP server、markdown 双向同步、音乐控制、系统 HUD、文件中转、项目 / 标签 / 子任务 / 重复任务、自己的同步（多设备只通过 Apple Reminders 的列表）、iPhone App、日历、多用户。Todo tab（#41）另外不做：Perch 自己的到期提醒 / 推迟（#53 设时间时加的 alarm 是提醒事项里的 alarm，由 Reminders 自己通知，不算 Perch 自己的提醒）、notice 转 task、agent 给人留 todo、在刘海面板里打字或任何输入语法、删除确认 / 撤销。Reminders（#50）另外不做：用 CLI 或 perchd 改勾选的列表（#70，只在 Lists… 窗口里）、`inbox.md` 里选列表的语法、跨账户挪 todo、没有权限时的本地 todo 模式、迁移旧的本地 todo、在提醒里写任何 Perch 专用的标记、把 Doing 同步到 Reminders / 手机（任何形式）、限制 Doing 的条数、右键菜单或编辑器里的 Doing、能点的优先级胶囊、request / notice / 等待中的 task 进 Reminders、todo 影响收起态（右翼的静态图标和数除外，#56）。
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
- ~~全局快捷键默认值~~ 已定（M2）：快速录入 ⌥⇧Space（`defaults write dev.perch.app QuickEntryHotKey "ctrl+opt+n"` 可改）；⌥⇧A / ⌥⇧D 批准 / 拒绝队首请求、⌥⇧O 跳转，M4 实现。M8 起快速录入随 todo UI 下线（#19 已删），⌥⇧A / D 回答面板上第一个 request、⌥⇧O 跳到等得最久的 Needs you 会话。2026-10-15（#43）起 ⌥⇧Space 打开 todo 弹窗，同一个 `QuickEntryHotKey` 可改（重启生效）。
- ~~Claude 桌面 App 里的会话能否沿父进程链找到 agent 的 pid~~ 已定（M7 实测）：能。桌面 App 每个会话一个 `claude` 进程（`Claude` → `disclaimer` → `claude`），会话进程退出就移除。Codex 桌面 App（ChatGPT.app）所有会话共用一个 `codex app-server` 进程，只有退出 App 才会按 pid 清掉。
- ~~全屏 App 下刘海面板是否可见~~ 已定（M8 实测）：可见。`NotchPanel` 是 `.fullScreenAuxiliary` + `.canJoinAllSpaces`、层级在菜单栏之上，全屏 Ghostty 里能悬停展开、能看到脉冲。
- ~~`SMAppService` 在 ad-hoc 签名、未公证的 App 上能不能用~~ 已定（2026-10-12 实测，#28）：能。ad-hoc 签名、没有 TeamIdentifier 的测试 bundle 调 `SMAppService.mainApp.register()` 后状态 notFound → enabled，`unregister()` 后回到 notRegistered，所以不需要给 App 另装 launchd agent 兜底。注销 / 重新登录后真的启动、出现在 系统设置 → 通用 → 登录项、菜单里取消后消失：2026-10-12 维护者在第二台 Mac 上验收通过。
- Perch.app 的签名（#51）：现在是 ad-hoc 签名，designated requirement 改成 `identifier "dev.perch.app"`（`scripts/bundle-app.sh`），Reminders 权限才能跨重新编译和升级保留（默认的 cdhash 每次编译都丢，探针验证过）。已知风险：任何自称这个 bundle id 的 App 都继承权限。自签证书或 Developer ID 留到公开分发之前再定；hardened runtime 没开，不需要 entitlement。
- hook 等刘海的超时：先用 20 秒（M4 定，`perch hooks install claude-code --wait N` 可改），用一周后再看。
- ~~开源许可证~~ 已定（2026-10-08，#4）：MIT，见 `LICENSE`。借来的第三方文件保留自己的版权头和许可证（NotchDo 是 MIT，`CGSSpace.swift` 是 MPL-2.0），Boring Notch（GPL-3.0）仍然不能碰。
