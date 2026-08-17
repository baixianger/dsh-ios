# DSH iOS 功能真实性修复状态

> 日期：2026-08-17  
> 验收基线：`FUNCTIONAL_PARITY_AUDIT.md`

## 本轮已完成

- 消费 `workspace.list.archivedSessionIds`，归档会话不再回流到工作区、搜索、平铺列表或选择状态。
- Sidebar 将 Search 与 View Options 分离；View Options 支持 Workspace / In One List 和 Manual / Last Updated，平铺视图去重并保留 Ungrouped 会话。
- Rename editor 等待 Host 成功后才关闭并保留可重试错误；Workspace 删除有明确确认；新建 Workspace 失败不再静默关闭。
- 已发送历史消息移除错误领域的 Edit / Regenerate / Delete，仅保留真实 Copy / Feedback / Branch。
- 已开始 Session 的 Agent preset 改为只读标签，不再调用被 Host 锁定的 `agentPreset.select`。
- Slash commands 改为按 Session 调用真实 `commands/list`；已识别命令通过 `commands/execute`，未知命令不会进入模型 prompt。
- 当前 Session 的 Access 改为 `/permission <preset>`；Full Access 必须二次确认。
- Settings 隐藏远端不可执行的 Agent preset Delete；Credential 遵守 Host `writable`，只读凭证无法打开编辑且模型层再次拒绝写入。
- 用户发起的核心 mutation 已增加可见错误反馈；后台 refresh 仍允许非阻塞降级。

## 自动化与运行时验收

- Mac mini 隔离构建：`BUILD SUCCEEDED`。
- 单测：8 tests / 0 failures。
  - `TranscriptBuilderTests`: 4
  - `SessionCommandTests`: 3
  - `WorkspaceListProjectionTests`: 1
- iPhone：Search/View Options、6 个动态命令、命令输入 hint、历史动作、只读 Mode、Full Access 取消、自定义 preset 无 Delete 均通过。
- iPad：Welcome/Composer、Sidebar、View Options、真实 Session、只读 Mode 均通过，无重叠裁切。
- 证据：`/tmp/dsh-readonly-controls-evidence.20260816-v2/`。

## 真机部署

- Xiang Bai’s iPhone：`databaseSequenceNumber 2692`，安装并启动成功。
- Real Rich and Beauty Pai：`databaseSequenceNumber 1640`，安装并启动成功。
- 两台使用同一签名构建产物。

## 尚未关闭的审计项

- 真正的 Queue Dock（pending queue 的 edit/remove/steer），本轮仅移除了错误地作用于历史消息的入口。
- Web 的服务端全文 Session Search、拖动重排、pending interaction/descendant running 等完整 Sidebar parity。
- Models/Plugins 的完整 Web 配置面与 preset authoring/document 能力。
- 当前 Host 没有只读 credential 数据，也没有单个 Workspace 超过 3 条可见 Session；这两项的 UI 分支由代码与单测覆盖，仍需合适数据做截图验收。
- 大型 Session 的初始历史分页/解码性能优化仍是独立待办。
