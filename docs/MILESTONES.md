# 里程碑

每一步都能独立验证再往下走；第 3 步完成时产品已经能日常使用。当前：**M2**。

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
- [ ] 全局快捷键弹快速录入
- [ ] `due_at` 到时：系统通知 + 刘海脉冲
- [ ] 验收：CLI 调用到刘海更新 ≤ 200 ms

## M3 — Claude Code 被动接入

- [ ] `hooks/` 下的适配脚本：`SessionStart` / `Stop` 维护 Live Activity；`Notification` 生成 waiting；`Stop` resolve 并发 notice
- [ ] `perch hooks install claude-code` 写 `~/.claude/settings.json`，`uninstall` 干净移除
- [ ] 验收：跑一个需要权限的任务，刘海变橙；跑完后 notice 出现并自动消失

## M4 — PermissionRequest + 白名单

- [ ] `PermissionRequest` 适配：`perch add --kind request --wait`，超时不返回决定
- [ ] 白名单配置文件 + 默认值；白名单外只显示"去终端"
- [ ] 展开态 request 行：完整命令原文 + Allow / Deny / 终端；⌥⇧A / ⌥⇧D 处理队首
- [ ] 验收：刘海里 Allow 一次 `npm test`，终端不弹提示；`rm` 只显示"去终端"；超时后终端提示正常弹出

## M5 — Codex 复用

- [ ] 同一套脚本，只改返回 JSON 的分支（`behavior`）；`perch hooks install codex` 写 `~/.codex/hooks.json`
- [ ] 验收：同 M3、M4

## M6 — Hermes HTTP 接入

- [ ] 容器内 `curl host.docker.internal:7331/rpc` 能 add 和 respond
- [ ] 验收：Hermes 阻塞时刘海变橙，respond 后继续
