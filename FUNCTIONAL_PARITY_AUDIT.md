# DSH iOS 功能真实性与 Web 对齐审计

| 项目 | 内容 |
|---|---|
| 日期 | 2026-08-16 |
| iOS 工作树 | `/Users/baixianger/personal/dsh-ios` 当前未提交工作树 |
| Web 基线 | Mac mini `/Users/baixianger/personal/deepseek-harness` commit `9455e3620e6023fc35718a74aa418144b4ed668b` |
| Web 观察地址 | `http://100.91.91.43:8080` |
| 审计性质 | 只读；未修改源码、未调用写入型 RPC、未安装 App |

## 结论

这不是几个孤立按钮失效，而是三类问题叠加：

1. iOS 没有消费完整的后端状态，例如完全忽略 `workspace.list.archivedSessionIds`。
2. 一些 UI 调用了真实 RPC，但调用了错误领域或错误对象，例如把已发送消息交给 Queue 变更接口。
3. 38 处空 `catch {}` 把后端拒绝、网络错误和参数错误全部表现成“按了没反应”。

优先级建议：先修 Archive 投影和历史消息假操作，再建立统一 operation state/error surface，随后补 Sidebar View Options 与动态命令目录。

## A. iOS 已展示、但失效或语义错误的功能

### A1. Archive 已写入后端，但 iOS 又把会话显示出来 — High

- iOS 的 `archiveSession` 正确调用 `workspace.archiveSession`，之后却只刷新 `session.list`。
- `loadWorkspaces()` 只解析 `workspace.list.items`，完全丢弃同一响应中的 `archivedSessionIds`。
- `conversations(in:)` 只按 Workspace membership 和 `blank` 过滤，不排除归档 id。
- 2026-08-16 的只读 RPC 证据显示后端已有 9 个 `archivedSessionIds`，其中多个仍位于 Workspace 的 `sessionIds` 中。这证明用户的 Archive 操作确实成功写入过后端；失败的是 iOS 的可见性投影。
- Web 规范：archive-set echo 到达后，该 Session 应从 Workspace、Ungrouped、搜索和 flat list 全部消失；日志和 Workspace accounting slot 保留。

证据：

- iOS：`App/AppModel.swift:183-190, 215-220, 258-262`
- 实时响应：`workspace-list.json`
- Web：`packages/client/ui-workspace/README.md`

### A2. 历史消息的 Edit / Regenerate / Delete 是接错接口的假功能 — High

- iOS 对所有带 `messageId` 的已发送消息展示“编辑 / 重新生成 / 删除消息”。
- 三个动作全部调用 `session.updateQueue`，并把 durable transcript 的 `messageId` 当作 Queue 的 `itemId`。
- DSH Web/runtime 契约明确：`session.updateQueue` 只编辑、删除或 strict-steer **尚未发送的 queued occurrence**。
- Web 还明确规定“Sent user messages cannot be edited”。重新生成也不是 `steer`：strict steer 是把一个排队消息移入当前正在运行的 turn，而不是重新生成历史回答。
- 因为错误被空 `catch {}` 吞掉，用户看到的就是三个无响应按钮。

证据：

- iOS：`App/Views/MessageBubble.swift:154-189`
- iOS：`App/SessionModel.swift:197-225`
- Web：`packages/client/ui-conversation/README.md` 的 QueueDock、Known Limitations
- Web：`packages/client/runtime/README.md` 的 `Session.updateQueue()` 契约

正确方向：历史消息只保留 Web 实际支持的动作；Queue 的 edit/remove/strict-steer 应放进独立的 Queue Dock，并使用 Queue snapshot 的 item id。

### A3. 已开始 Session 的 Mode/Agent preset 选择器必然被 Host 拒绝 — High

- iOS 会话右上 More 菜单提供“模式”，对当前 Session 调用 `agentPreset.select`。
- DSH Web 官方契约明确：Session 一旦开始，preset 固定；Host 返回 `agent-preset-locked`。会话标题区只显示只读 preset label。
- iOS 随后吞掉错误并关闭 sheet，形成完整的假交互。

证据：

- iOS：`App/Views/SessionDetailView.swift:144-160, 221-248`
- iOS：`App/AppModel.swift:122-125`
- Web：`packages/client/ui-agent-preset/README.md`

### A4. Slash Command 菜单同时缺真命令、展示假命令 — High

- iOS 硬编码：`compact, plan on, plan off, goal, title, fork, cwd`。
- 当前真实 Session 的 `commands/list` 返回：`compact, export, feedback, goal, permission, plan`。
- 因此 iOS 缺 `export / feedback / permission`，却展示服务端不存在的 `/title /fork /cwd`。
- `/plan on` 也不是 Web 的 toggle 命令；真实 hint 是 `[off|message]`，所以 `on` 会被解释为 plan message，而不是一个正式 on 子命令。
- Web 会按 Session/preset 动态读取命令目录，并在 preset 变化时刷新；硬编码无法适应不同 preset/plugin composition。

证据：

- iOS：`App/Views/ComposerView.swift:5-20, 40-43`
- 实时响应：`commands-list.json`
- Web：`packages/client/ui-commands/src/client/service.ts`

### A5. Agent preset 的 Delete 在 iPhone/iPad 远程客户端上不可执行 — High

- iOS 对每个 user preset 展示“删除”，直接调用 `agentPreset.remove`。
- Web 官方契约明确：`agentPreset.read/copy/openDocument/remove` 都是 loopback-pinned；LAN iOS 客户端不能调用。
- iOS 未根据能力隐藏/禁用该操作，且错误被空 `catch {}` 吞掉。

证据：

- iOS：`App/Views/SettingsView.swift:404-418`
- iOS：`App/AppModel.swift:105-109`
- Web：`packages/client/ui-agent-preset/README.md`

### A6. Filter 实际只是本地搜索，名称和图标承诺了不存在的 View Options — Medium

- 按钮只切换一个 `TextField`；没有过滤设置页或菜单。
- 搜索只在已经加载的 `model.sessions` 中按 title/cwd 做本地 substring match。
- 没有 Web 的 Group by Workspace / In one list，也没有 Manual / Last updated。
- 没有 Web 的 250ms server content search、snippet、取消旧请求、20 条上限和失败 warning。
- 文案却是“Filter Workspaces/过滤工作区”，因此用户认为它无法设置 filter 是正确判断。

证据：

- iOS：`App/Views/SidebarView.swift:37-61, 78-104, 187-194`
- Web 观察：`screenshots/view-options.png`
- Web：`packages/client/ui-workspace/README.md`

### A7. Rename 调用真实 RPC，但交互把所有失败伪装成成功 — Medium

- `session.rename` 本身是正确 RPC。
- 点保存后 alert 立即关闭，不等待结果；没有 pending、输入校验或错误文本。
- RPC error 被空 `catch {}` 吞掉，失败后标题不变且没有任何反馈。
- Workspace rename 有完全相同问题。
- Web 的 rename dialog 会保留 pending 状态，并把 Host 的 `title-invalid` 显示在 dialog 中。

证据：

- iOS：`App/Views/SidebarView.swift:165-184`
- iOS：`App/AppModel.swift:251-255, 290-294`
- Web：`packages/client/ui-workspace/README.md`

### A8. 当前会话的 Access 控件修改了全局 default，而非当前 Session — Medium

- Active Session Composer 的 Access 菜单调用 `AppModel.setPermission()`。
- 该函数写 `settings.update` 的 `permission.defaultPreset`；这是之后会话的默认设置，不是当前 Session 的权限切换。
- Web 的当前会话 Access seat 执行 `/permission <preset>`；`danger-full-access` 还需要风险确认。
- 因此 iOS 控件即使 RPC 成功，其作用域也与界面承诺不符。

证据：

- iOS：`App/Views/SessionDetailView.swift:117-131`
- iOS：`App/AppModel.swift:320-338`
- Web：`packages/client/ui-conversation/README.md`

### A9. Workspace Delete 是立即提交、无确认、无错误 — Medium

- 菜单里的 destructive Delete 直接调用 `workspace.delete`。
- Web 会显示 retention boundary、阻止重复提交、失败时保持确认窗口；成功后 Session 进入 Ungrouped。
- iOS 没有确认，也没有 Ungrouped surface，失败仍无提示。这不是假 RPC，但当前实现既危险又无法解释结果。

证据：

- iOS：`App/Views/SidebarView.swift:248-259`
- iOS：`App/AppModel.swift:297-305`
- Web：`packages/client/ui-workspace/README.md`

### A10. Credential 编辑器忽略 Host 的 `writable` 能力 — Medium

- 数据模型解析了 `CredentialView.writable`，Settings 页面却无条件让每条 Credential 可编辑、保存、清除。
- 在只读部署中，这些按钮会出现但必然失败；当前测试 Host 返回 writable=true，所以这是跨部署的确定性缺陷，不是当前 Host 的即时故障。
- 保存/清除同样先关闭 sheet，再静默吞错。

证据：

- iOS：`App/Models.swift:584-589`
- iOS：`App/Views/SettingsView.swift:257-280, 486-519`
- 当前只读响应：`credentials-describe.json`

## B. Web 已实现、iOS 尚未实现的实质功能

### Sidebar / Workspace browser

| Web 能力 | iOS 状态 |
|---|---|
| View Options：Group by Workspace / In one list | 未实现 |
| Session Order：Manual / Last updated | 未实现 |
| Workspace drag reorder（Host durable） | 未实现 |
| Session drag reorder（real Workspace durable） | 未实现 |
| Ungrouped 分组 | 未实现 |
| 搜索正文、rank、snippet、debounce/cancel/warning/20条上限 | 只有 title/cwd 本地搜索 |
| archivedSessionIds 全局过滤 | 未实现，导致 Archive 视觉失败 |
| Waiting for approval / plan review / answer 状态 | 侧边栏只显示 running spinner |
| descendant subagent running count / unviewed completion | 未实现 |
| Workspace delete retention confirmation/error | 未实现 |
| Rename pending/Host error | 未实现 |

说明：Web 默认展开 5 条、iOS 默认 3 条是用户明确指定的设计差异，不列为缺陷。

### Conversation

| Web 能力 | iOS 状态 |
|---|---|
| Queue Dock：排队消息展示、折叠、编辑、删除、strict steer | 未实现；错误地把动作放到了历史消息上 |
| Busy Enter 的 Queue/Steer 偏好与 Cmd/Ctrl+Enter 互换 | 未实现 |
| 动态 Session/preset command directory | 未实现，当前为硬编码错误目录 |
| 当前 Session `/permission` + Full Access 风险确认 | 未实现；错误写成全局默认 |
| Session preset 只读 header label | 未实现；反而提供无效的 live picker |
| Todo plan strip | 未实现；只有 planActive banner/Goal UI |
| Context injection / recalled-session source disclosure | Chat 主流未实现，只在 Trajectory 有泛化记录 |
| Manual compaction checkpoint row + summary disclosure | Chat 主流未实现 |
| Queue/steering durable handoff | 未实现 |
| Web 对已发送消息的合法动作边界 | iOS 展示了不合法的 Edit/Regenerate/Delete |

### Settings

| Web 能力 | iOS 状态 |
|---|---|
| General：Language | 未实现；iOS 仅跟随系统本地化 |
| General：busy Enter Queue/Steer | 未实现 |
| Models：provider create/edit/delete | 未实现 |
| Models：base URL、API protocol、display name | 未实现 |
| Models：模型目录编辑、contextWindow/maxTokens | 只读展示 |
| Models：Fetch available models | 未实现 |
| Agent presets：copy/create | 未实现 |
| Agent presets：read-only viewer / broken state / capability gates | 未实现 |
| Agent presets：open/reveal path | 未实现（远程端应显示路径而非伪装可打开） |
| Plugins：Configuration tab（bash/agent-loop/web-search 等） | 未实现 |
| Plugins：Inventory detail disclosure、entry id、effective config、retry | 只有简化只读列表 |

## C. 系统性问题

### C1. 38 个空 `catch {}` 让真实功能看起来像假按钮 — High architecture risk

- `AppModel.swift`：20 处。
- `SessionModel.swift`：18 处。
- 受影响范围包括 presets、providers、credentials、workspace rename/delete/archive、permission、model select、subagents、skills、trajectory、queue mutation、feedback、goal actions、cancel 等。
- 这使 UI 无法区分：离线、权限拒绝、参数错误、state conflict、locked capability、not-found、timeout。

最低修复基线：所有用户发起的 mutation 必须有统一的 `idle/pending/succeeded/failed` 状态；失败应保留原弹窗或菜单上下文并显示 Host error code/message。后台 refresh 可降级，但不能静默吞掉影响当前动作的错误。

### C2. iOS 自己维护功能目录，而不是读取 Host capability/projection

已经造成：

- Slash commands 与真实 Session composition 漂移。
- Agent preset authoring/loopback capability 未应用到按钮可见性。
- Credential writable 未应用到编辑能力。
- archived projection 被忽略。
- started-session preset lock 被 UI 违反。

方向：UI 应以 Host 返回的目录、projection 和 capability flag 为真源；若没有 capability，隐藏或解释性禁用，不渲染一个注定失败的按钮。

## 建议修复顺序

1. **数据正确性**：解析并应用 `archivedSessionIds`；建立 archived set 单一投影。
2. **移除假功能**：删除历史消息 Edit/Regenerate/Delete；删除 started-session Mode picker；隐藏远程 preset Delete。
3. **操作反馈层**：替换 38 个空 catch，先覆盖所有 mutation。
4. **Sidebar parity**：将 Search 与 View Options 分成两个按钮；补 grouped/flat、manual/recency、Ungrouped。
5. **命令与权限**：动态读取 `commands/list`；当前 Session Access 走 `/permission` 并加 Full Access 确认。
6. **真正的 Queue Dock**：从 Host queue snapshot 渲染，并把 edit/remove/steer 放回正确对象。
7. **Settings capability gating**：尊重 writable/authorable/hasDocument/broken；补 Models 与 Plugins 的真实配置面。

## 审计证据文件

- `screenshots/initial.png`：Web Sidebar 初始界面。
- `screenshots/view-options.png`：Web Group by / Order by 菜单。
- `screenshots/settings.png`：Web Settings 目录和 General 控件。
- `workspace-list.json`：当前 Host Workspace 与 9 个 archived ids。
- `commands-list.json`：当前真实 Session 的动态命令目录。
- `settings-describe.json`：当前 Host settings capability/schema。
- `credentials-describe.json`：当前 Host credential configured/writable。

## 审计边界

- 本报告没有把 Web 已明确列为 Known Limitation 的 Session deletion/unarchive 当成 iOS 缺失。
- 没有把 iOS 原生文件/照片/语音能力当作 Web parity 缺口或假功能。
- Web 观察期间连接曾出现部分服务警告；所有高优先级结论都同时由 iOS 源码、当前只读 RPC 或 Web package contract 支撑，不依赖单次视觉观察。
