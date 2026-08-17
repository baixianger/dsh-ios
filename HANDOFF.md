# DSH iOS 客户端 — 项目交接文档

> 写给接手的 agent（Codex）。本文档是当前工程状态的权威说明，接手后请以实际代码/工具结果为准核对，再继续。

> 构建与模拟器验证必须先阅读根目录 `COMPUTE_RESOURCE_POLICY.md`。默认在 Mac mini 的隔离目录验证；当前工作电脑不启动 Simulator，两台机器都不得同时运行多台模拟器。

## 0. 2026-08-16 本机续作状态

- 2026-08-17 已完成首轮功能真实性修复。原始审计保存在 `FUNCTIONAL_PARITY_AUDIT.md`，逐项修复与剩余项保存在 `FUNCTIONAL_REPAIR_STATUS.md`。Mac mini 隔离构建成功、单测 8/8，通过 iPhone/iPad 真实后端 UI 验收；证据 `/tmp/dsh-readonly-controls-evidence.20260816-v2/`。同一最终构建已部署并启动：iPhone sequence `2692`、iPad sequence `1640`。

- 已新增 Codex/ChatGPT iOS 参考 `CODEX_UI_REFERENCE.md`，并把 8 张原始参考图保存到 `docs/ui-reference/codex/`。第 6 张补充 stream、reasoning 与工具活动，第 7/8 张记录浅色侧边栏目标与重做前差距。规范已改为严格的 DSH 能力映射：没有现有状态/RPC 的 Speed、Pin、目标用时、文件聚合等不得实现或伪造。
- 已确认本机 `main` 与 `origin/main` 同步在 `971b300`；续作结束前再次 fetch，远端无新增提交。
- 已完成“思考过程 + 连续工具调用”统一折叠：`TranscriptBuilder` 在模型层生成稳定展示条目，`ActivityGroupCard` 默认显示一条 Codex 风格紧凑摘要；展开后每个 reasoning/tool 活动为单行，再按行查看输出。回答正文和反馈 messageId 保持不变。
- 消息正文长按仅启用系统文本选择。整条消息的 context menu/放大预览已移除，编辑、重新生成和删除位于尾部 `…`。
- 欢迎页官方鲸鱼独立为 62 × 48pt 一行，标题位于其下。设置页已按 Web 导航重组为 Connection & Pairing、General、Models、Agent presets、Plugins，仅呈现现有 RPC 能力。
- 会话页已按第 6 张参考继续收敛：活动折叠改为平面轨迹样式；Composer 合并为单一浮动材质容器；发送/停止由 `isRunning` 驱动；目标卡移到输入器上方并压缩为可展开胶囊；jobs/subagents 仅在真实数据存在时显示状态胶囊。
- 已补 `DshAppTests`，覆盖统一分组、仅思考、仅工具、无正文 reasoning 等 4 个边界场景；iPhone 模拟器执行 4/4 通过。
- 已补侧边栏交互式手势：左边缘右滑跟手打开，打开后左滑跟手关闭，35% 阈值并支持回弹；iPhone 复测通过。
- iPhone/iPad UI 降级走查通过：iPhone 主内容右移 320pt + 遮罩；iPad 主内容不位移、无遮罩且保持可操作；Composer 无重叠。
- `sidebar.toggle` 已具备 accessibility label 与 identifier。聊天页坐标级 AX hierarchy 可读，但 AXe 完整树枚举仍偶发漏掉该按钮，保留为自动化工具兼容风险。
- 真实会话在模拟器消息区为空，因此统一折叠块尚未完成真实数据运行时截图验收；分组单元测试与完整 App 构建均已通过。
- 该历史阻塞已解除：Mac mini 模拟器通过 `http://100.91.91.43:8080` 连接本机 DSH，使用 49 turns / 516 steps 的真实会话完成 Activity、长按文本选择与 Trajectory 全链路验收。
- UI 证据：`/tmp/dsh-ui-verify.xrkSaj`、`/tmp/dsh-ui-retest.gqN4oj`（临时目录，机器重启或清理后可能消失）。
- 最新会话页视觉走查证据：`/tmp/dsh-ui-latest.1NtBPV`。iPhone/iPad 单一浮动 Composer 均无重叠、越界或裁切；目标胶囊打开/关闭正常。真实会话仍无 reasoning/tool 数据，平面活动折叠尚待有数据时补拍运行时证据。
- 最新侧边栏重做证据：`/tmp/dsh-sidebar-verify.cgfQ3U`。iPhone 已确认纯白平面背景、扁平项目/会话行、按需搜索、固定底部新建聊天与设置按钮；搜索展开/收起及列表滚动通过。iPad 无重叠裁切。验证后又移除了会挤压品牌标题的侧栏内 X；关闭仍由右侧主页面按钮、遮罩和左滑手势承担。
- 后续按用户反馈继续修正：抽屉拖动由 `@GestureState` 改为持久 `@State`，松手时 sidebar state 与 drag offset 在同一个 spring transaction 中归位，避免手势结束先归零造成跳帧；侧栏底部移除独立材质横条；每个项目默认展示最近 3 条聊天，其余显式展开/收起。
- 上述修正的 iPhone 证据在 `/tmp/dsh-sidebar-latest.XDvhkS`：慢速右拖中间帧与最终全开连续，项目 3 条默认折叠和展开/收起均通过。会话页右上统计/更多已移除手工圆形背景，改为原生 `ToolbarItemGroup`，系统单层材质、统计 sheet 和更多菜单验证通过。左拖可正常完成关闭，但现有中间帧抓取过早，尚不能用证据排除全过程中的细微跳帧。
- 最终抽屉层级统一为：iPhone、横屏与 iPad 的 `SidebarView` 固定在 z=0 底层，`mainSurface` 位于 z=1 并随进度右移；主体左缘阴影压向侧栏。抽屉是非模态并排状态，不使用 scrim 或透明点击拦截层，主体始终保持正常亮度和完整交互。上下系统区域使用同色背景，但控件继续遵守安全区。
- 最终证据：`/tmp/dsh-unified-sidebar.RTEUMZ`。Session 行已移除前置图标，每项目默认 3 条并以纯三点展开；新建聊天采用首条消息发送时才创建 session 的惰性流程，重复进入不会新增空白记录。实体 iPad 最新安装序号 `1496`。

## 1. 项目是什么

把 DeepSeek Harness（DSH）的 **web 客户端** 以 C/S 架构迁移到 **iOS 原生 App**（SwiftUI，iOS 17+，iPhone + iPad 双端），App 通过 HTTP RPC + WebSocket 直连 DSH 后端。

- 工程根目录：`/Users/baixianger/personal/dsh-ios`
- 工程名：`DshApp`，bundle id：`com.baixianger.dshios`（xcodegen 生成 `DshApp.xcodeproj`）
- 目标：功能与 web 端对齐（侧边栏/会话/工作区/设置/审批/提问/计划/目标/子代理/任务/技能/附件/消息反馈），responsive design。

## 2. 代码结构

- `project.yml` — xcodegen 配置（sources: `App` + `Sources/DshClient`；`TARGETED_DEVICE_FAMILY: "1,2"`；`info:` 块含 ATS 例外 + 麦克风/语音权限）。
- `Sources/DshClient/` — 客户端库：
  - `Wire.swift` — 信封 `ClientRequest{type:"client-request",rpcId,method,payload}`、`ServerResponse`、`ServerRequest`、`RpcError`。
  - `DshClient.swift` — `call(method,payload)`（POST /api/{method}）；`callRemote(ns,method,args)`（POST /api/{ns}/{method}，payload 包成 `{args: ...}`）；`respond`；`muxEvents`/`hostEvents`（WebSocket）；`exportSession`。
  - `JSONValue.swift` — 无损 JSON 值。
- `App/` — App target：
  - `AppModel.swift` — 全局状态（baseURL/client/sessions/workspaces/选中态/agentPresets/providers/credentials/modelCatalog/plugins/discoveredHosts/permission/审批/提问/`showSidebar`/`showSettings`）。方法：loadSessions/loadWorkspaces/loadAgentPresets/loadProviders/loadCredentials/loadModelCatalog/loadPermission/loadPlugins/discoverHosts/testConnection/createSession/renameSession/archiveSession/forkSession/createWorkspace/renameWorkspace/deleteWorkspace/selectProject/selectConversation/newChat/setPermission。
  - `SessionModel.swift` — 单会话状态（items/feedback/modelGroups/currentProvider/currentModelName/**currentEffort**/draft/goal/stats/tokenUsage/planActive/jobs/subagents/skills）。方法：loadHistory/loadModels/selectModel/loadFeedback/toggleFeedback/setFeedbackNote/send/cancel/edit/steer/remove/goal 系列/apply(event)/foldHistory。
  - `Models.swift` — SessionSummary/ChatItem/Workspace/SubagentEntry/JobView/ModelInfo/ModelGroup/GoalState/ApprovalWait/QuestionWait/ReadCard/DiffCard/CredentialView/SkillEntry/AgentPreset/ProviderView/PluginEntry/MessageFeedbackItem。
  - `App/Views/` — 见下。
- `tools/dsh-proxy.js` — 反向代理（0.0.0.0:8080 → 127.0.0.1:3080，重写 Host 为 loopback 以通过 DSH 信任栅栏）。

## 3. 关键视图（App/Views/）

- `SessionListView.swift` — **统一分层抽屉容器**（不使用 NavigationSplitView）。所有尺寸都采用固定底层侧栏 + 可移动上层主体：主内容随手势最多右移 320pt，圆角和左缘阴影随进度连续变化。背景与 NavigationStack 使用同一连续圆角裁切（iPhone 约 44pt、iPad 约 28pt），避免方形内容层盖住外层圆角。主体视觉表面延伸到物理屏幕上下边缘；正文与控件仍遵守安全区。展开后主体不变暗、不锁定，可继续滚动、输入和操作；支持左缘右滑打开、左滑关闭和工具栏按钮切换。
- `SidebarView.swift` — 浅色扁平抽屉：官方鲸鱼 + deepseek HARNESS 品牌入口；Workspace 标题同行提供过滤/添加；34pt Workspace 行使用 Web 同源闭合/展开文件夹，32pt Session 行无前置图标；每组默认 3 条并以无缩进 `…` 展开。底部固定新建会话与设置。
- `WelcomeView.swift` — 无 Session 选中时默认进入 `Into the Unknown` 欢迎页；点击侧边栏品牌也返回欢迎页。欢迎 Composer 上方只能选择 `workspace.list` 与 `agentPreset.list` 的真实值，且控制行相对输入框额外内收；全局新建入口必须先选已有 Workspace，或输入 DSH 主机绝对目录调用 `workspace.create`；首条发送时才 `session.create`。
- `SessionDetailView.swift` — 会话详情：计划横幅 + GoalCard + 消息列表 + 审批/提问卡 + Composer。顶部工具栏有 **ⓘ**（打开 StatsSheet）+ **⋯**（菜单：模式/模型/工作/轨迹）。列表读取 `SessionModel.transcriptEntries`，用稳定展示条目渲染消息或统一活动块。
- `TrajectoryView.swift` — 会话 `…` 内的 Trajectory / 轨迹底部抽屉。直接投影 `session.history` 原始事件，提供时间条、Duration/Turns/Calls/Search、Turn 分段、较早历史分页与原始事件/host view 详情。
- `MessageBubble.swift` — 消息气泡（用户/assistant/工具/图片）+ 纯图标操作行（复制/赞/踩/备注/Branch）+ 尾部 `…` 操作菜单 + Codex 风格紧凑 `ActivityGroupCard`。正文长按只做文本选择；朗读已删除；Branch 只给最后一条已完成 Assistant 消息，调用真实 `session.fork`。
- `ComposerView.swift` — 22pt 连续圆角输入区；下行「+」（PhotosPicker）、DSH 官方三态 Access 盾牌、模型、🎤 语音与发送/停止。模型标题仅在所选模型声明 `reasoning` 时追加 Host 提供的强度；无 reasoning 的 Provider 不显示也不提交虚构强度。
- `SessionExtras.swift` — StatsBar(已弃用)/GoalCard/GoalEditorSheet/ReadCardView/DiffCardView/`ModelPickerSheet`(拍扁：选模型 + 思考强度分段)/`WorkSheet`/SubagentHistoryView/OfflineReminderView/`StatsSheet`；自由函数 `effortLabel`、`permissionName`。
- `SettingsView.swift` — Web 术语和顺序的自适应设置：Connection & Pairing（iOS 特有）、General（Appearance + 默认 Agent preset）、Models（Provider + API Key + 模型目录）、Agent presets、Plugins。iPhone 从五项目录进入系统 push 详情；iPad 保留弹窗内双栏并默认 General。
- `WelcomeView.swift`（含 `BlankChatView`）、`DSHBrand.swift`、`MarkdownText`、`Theme.swift`（`Color.dsAccentBlue = #0A84FF`、dsSurface*）、`SpeechInput`、`HostDiscovery`。

## 4. 构建 / 安装

### 生成工程
```bash
cd /Users/baixianger/personal/dsh-ios
xcodegen generate
```

### 模拟器（无需签名）
```bash
xcodebuild -project DshApp.xcodeproj -scheme DshApp -configuration Debug   -destination 'generic/platform=iOS Simulator' build
```
已 booted 的模拟器：iPhone 16e `F5DB0E80-1A34-4B6D-802F-072EE85FB3D0`、iPad A16 `1D4D1E9E-352C-44EF-88E9-AE9B2CA38F7D`（`xcrun simctl boot <udid>`）。

### 真机（需签名）
设备 UDID `00008140-000A4C422EB8801C`（devicectl 标识 `1F8FEF67-8E08-5BEC-8867-E0944ED789FB`，iPhone 16「Xiang Bai’s iPhone」）。
```bash
xcodebuild -project DshApp.xcodeproj -scheme DshApp -configuration Debug   -destination 'platform=iOS,id=00008140-000A4C422EB8801C'   -derivedDataPath build/DerivedData   DEVELOPMENT_TEAM=TN7ZDD72P2 CODE_SIGN_STYLE=Manual   PROVISIONING_PROFILE_SPECIFIER='match Development com.baixianger.dshios'   ENABLE_DEBUG_DYLIB=NO build

xcrun devicectl device install app --device 1F8FEF67-8E08-5BEC-8867-E0944ED789FB   build/DerivedData/Build/Products/Debug-iphoneos/DshApp.app
xcrun devicectl device process launch --device 1F8FEF67-8E08-5BEC-8867-E0944ED789FB com.baixianger.dshios
```
**签名注意**：
- 必须 `ENABLE_DEBUG_DYLIB=NO`，否则 Xcode 16 调试 dylib 会触发 `errSecInternalComponent`。
- 登录钥匙串要解锁（DSH 跑在 SSH/后台会话，GUI 解锁无效）：`security unlock-keychain -p <登录密码> ~/Library/Keychains/login.keychain-db`。
- 手机须解锁才能 launch（install 不需要解锁）。

## 5. 运行时环境

- DSH 后端：`node .../@deepseek-ai/dsh/lib/bin.js web`，监听 `127.0.0.1:3080`（仅 loopback），未鉴权，有 Host 信任栅栏。
- **代理**（iPhone 通过 Tailscale 访问的唯一通道）：`tools/dsh-proxy.js` 监听 `0.0.0.0:8080` → 127.0.0.1:3080。已由 **launchd 常驻**（`~/Library/LaunchAgents/com.baixianger.dsh-proxy.plist`，KeepAlive+RunAtLoad）。若「自动扫描」扫不到，先查代理是否在跑：`lsof -nP -iTCP:8080 -sTCP:LISTEN`。
- Tailscale：MagicDNS 后缀 `tail849fa3.ts.net`；macbook-air `100.91.91.43`、mac-mini `100.123.131.117`、iphone16 `100.83.106.12`。`HostDiscovery.candidates` 探的是 `http://<magicdns>:8080` 和 `http://<tailnet-ip>:8080`。
- DSH 源码参考（查 RPC/插件）：`~/.dsh/profiles/node_modules/@deepseek-ai/`（如 `dsh-message-feedback`、`dsh-host-plugin-inventory`、`dsh-api-gateway` 的 `lib/typert.host.js` 定义了远程服务）。

## 6. 架构要点 / 坑

- **不用 `@Observable` 宏**（DSH 沙箱下 swift-plugin-server 报错），全用 `ObservableObject` + `@Published`/`@EnvironmentObject`/`@ObservedObject`/`@StateObject`。
- **两套 RPC 协议**：
  - 普通方法：`POST /api/{method}`，payload 直接是参数（`session.list`、`workspace.list` 等）。
  - Typert 远程服务（gateway）：`POST /api/{namespace}/{method}`，payload 必须 `{"args": {...}}`。`messageFeedback/*` 用 `args.request`（单参数包一层）；`pluginInventory/list` 无参数用 `args:{}`。返回值分两种：messageFeedback 是 `{ok, value|error}` 业务联合；pluginInventory 直接是 `{entries:[...]}`。
  - 见 `DshClient.callRemote`。
- **assistant 消息的 messageId** 在 `SessionModel.applyMessage` 里从 `data["message"]["id"]` 捕获（反馈定位必需），不能丢。
- 草稿 `SessionModel.draft` 按会话隔离（SessionModel 在 AppModel.openSessions 缓存）。
- `NSAllowsArbitraryLoads=true`（HTTP 明文访问）。

## 7. 待办（交接给下一个 agent 重点）

### 已收口的高优先级验收
1. **Activity / 文本选择**：真实 reasoning/tool Session 已验证紧凑摘要、单行展开、详情展开与系统文本选择。
2. **Trajectory**：真实 `session.history` 已验证 `…` 入口、sheet、筛选、分页和事件详情。
3. **设置**：Connection & Pairing、General、Models、Agent presets、Plugins 已完成 iPhone 单栏与 iPad 双栏运行时验收。

### 当前待办
1. **大型 Session 加载优化**：trace 已定位无界初始历史与 `JSONValue` 解码；需要在获得实现授权后增加最近窗口/较早消息分页，并评估更快的 JSON 解码路径。
2. **iPhone 横屏最终回归**：Mac mini Simulator GUI 旋转未生效，仍缺当前最新版截图和层级证据。

### 低优先级 / 阻塞
3. **@file 引用**：阻塞——后端目录选择器是 macOS 原生 GUI picker，无远程目录列举 RPC（`dsh-host-directory-picker-*` 无 Typert remote），iOS 无法复用；需后端侧支持才可做。
4. **deliverables / trajectory**：web 端 client-side 聚合视图，未做（非显式清单项）。

## 8. 最近验证状态

- 2026-08-16 最终真实数据 UI 证据位于 `/tmp/dsh-final-ui-closeout.20260816/`：Thinking、活动摘要和展开工具行统一为 30pt；组间距 6pt；`run_code` 摘要为 `ran N commands`，行内显示真实 description 而非 JSON；Trajectory 在 iPhone 紧凑宽度使用三个不折行图标按钮，搜索框完整。
- Trajectory 的完整交互证据位于 `/tmp/dsh-final-activity-evidence.20260816/`：More 菜单入口、medium sheet、真实 record 详情、Turns、Calls、Search 均通过；消息正文长按只出现系统文本选择菜单，无整条消息缩放预览。
- 同一最终工作树已 clean arm64 构建并部署至两台实体设备：Xiang Bai’s iPhone `databaseSequenceNumber=2668`；Real Rich and Beauty Pai iPad `databaseSequenceNumber=1616`。两台均启动成功并保持运行。远端验证结束后 0 台 Simulator Booted。
- 随后修复欢迎页草稿控件与 Host 缓存：Model 不再被硬编码 disabled；Workspace 未选时仅发送按钮禁用；Model/Reasoning/Access 在 Session 创建前本地选择，首条发送时按 Access → session.create → session.selectModel → prompt 顺序应用。切换 Host 会完整清空并重载全部 host-scoped 数据，避免 Presets/Models 残缺。
- 最终欢迎页真实数据证据：`/tmp/dsh-welcome-controls-evidence.20260816/`。当前 Host 的 5 个 Presets（标准、PTC、极简、创造、Apple）完整可选；真实 Flash/Pro 与 Off/High/Max reasoning 可选；三种 Access 可选且盾牌/AXValue 即时更新；只做选择时 `session.list` 保持 19 → 19，无空 Session。最终双真机部署：Xiang Bai’s iPhone `databaseSequenceNumber=2676`；Real Rich and Beauty Pai iPad `databaseSequenceNumber=1624`，均启动并保持运行。

- iPhone/iPad Settings 自适应修复证据：`/tmp/dsh-settings-ipad-fix-evidence.20260816-v2/`。iPhone 从五项目录进入详情并可原生返回；iPad 弹窗固定显示左侧五项目录与右侧详情，默认 General，点 Models 仅更新右栏。内置 `code` preset 按稳定 id 显示为英文 `Code mode` / 中文 `PTC 编程模式`。同一 clean build 已部署：Xiang Bai’s iPhone `databaseSequenceNumber=2684`；Real Rich and Beauty Pai iPad `databaseSequenceNumber=1632`。
- 大型会话性能 trace：49-turn 会话默认 `session.history` 返回 55,240 events / 11.18 MB；HTTP 完整下载约 0.39s，当前 `JSONValue` 解码约 4.12s，`foldHistory` 约 0.335s，Trajectory 构建约 0.167s；模拟器首批正文约 4.59s 可见。瓶颈主要是无界初始历史和通用 JSON 解码，不是连接握手。仅取最近 10 条消息时降至 5,942 events / 1.16 MB，网络约 0.044s、解码约 0.442s。本轮仅诊断，尚未改变历史加载语义。
- iPhone 横屏最终回归仍受 Mac mini Simulator GUI 旋转失败阻塞；一次尝试后层级仍为 375×667，未误标通过。

- 2026-08-16 DSH Web 对齐版本已在 Mac mini 隔离目录 `/tmp/dsh-web-ui-build.snJAFw` 完成 generic iOS Simulator 构建，结果 `BUILD SUCCEEDED`；没有触碰远端脏工作树。远端已有其他任务的 `Nearto-Small` Simulator Booted，因此本轮未启动第二台设备。

- 2026-08-16 最新“主体视觉表面铺满物理屏幕”补丁已在 Mac mini 的隔离目录 `/tmp/dsh-main-surface-verify.sZmHLE` 完成 generic iOS Simulator 构建，结果 `BUILD SUCCEEDED`；证据已复制到本机 `/tmp/dsh-main-surface-remote-evidence`。
- 最新“新建聊天先选择已有项目或 DSH 主机目录”版本已完成真机 arm64 构建、Manual signing、安装和启动；Xiang Bai’s iPhone `databaseSequenceNumber=2628`。DeviceInteraction MCP 当时不可用，因此仅使用 `xcodebuild + devicectl`，没有真机截图/触控证据。
- 本轮未做运行时截图：Mac mini 当时已有 3 台其他任务的 Booted Simulator，按 `COMPUTE_RESOURCE_POLICY.md` 未抢占、未复用、未关闭。资源释放后须按 iPhone → shutdown → iPad 的顺序补测上下边缘、圆角、阴影、主体正常亮度与交互、安全区内容。
- 较早版本的统一抽屉、三条折叠、纯三点展开、无 session 前置图标及延迟创建会话已完成运行时验证；最终证据目录 `/tmp/dsh-unified-sidebar.RTEUMZ`，以 `ultimate-*` 为准。
- RPC 回环已验证：session.list / messageFeedback(list/put/delete/note) / pluginInventory.list / host.describe / workspace.list / agentPreset.list / skill.list / settings.describe / subagent.list / credentials.describe(需 refs 数组)。
