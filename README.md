# dsh-ios — DeepSeek Harness iOS 客户端（spike）

对 DeepSeek Harness web 后端（http://127.0.0.1:3080）的一个原生 Swift 客户端骨架。
iOS 端和 web 前端是**平等的两个 peer 客户端**，走同一条协议：

- 调用：POST /api/{method}
  请求  { "type":"client-request", "rpcId":"...", "method":"session.list", "payload":{} }
  响应  { "type":"server-response", "rpcId":"...", "result":{ "ok":true, "value":{...} } }
- 事件：下行专用 WebSocket
  ws://host/api/events.mux  （会话事件 / 审批 / 提问 / 队列 / 投影）
  ws://host/api/events.host （会话增删改 / workspace / 代理错误）
  每条文本帧 = { "type":"server-request", "rpcId":"...", "method":"session/subscribed", "payload":{...} }

## 本机跑 spike

    swift run dsh-spike
    swift run dsh-spike http://127.0.0.1:3080

输出：host.describe（typed）、session.list（raw JSON）、events.mux 前若干帧。

## 发现与连接

- 扫码配对：App 扫描 Server Shell 生成的一次性二维码；LAN、Tailnet 和用户自行配置的 HTTPS Server 使用同一种格式。
- 粘贴链接：相机不可用时可直接粘贴完整配对链接。
- 手动地址：高级用户可添加任何 iPhone 能访问的既有 HTTP/HTTPS Base URL。

### 可选：通过 dsh-network 安全配对

1. 在 Server 的 web profile 安装 `dsh-network`。插件继续让 DSH 只监听 loopback，
   另开带鉴权的 Gateway；不要把 3080 直接暴露到局域网或公网。

    dsh plugin --profile web add dsh-network

2. Tailnet Server 运行 setup。它把 Tailscale Serve 指向安全 Gateway，并在 Shell
   显示一个 5 分钟、仅可使用一次的二维码：

    dsh-network setup

3. 在 iOS App 的「设置 → 连接与配对」点二维码按钮并扫描。短期 access token 与
   可轮换 refresh token 存在 Keychain；过期后 App 自动续期。浏览器也能打开同一
   张二维码，换取 HttpOnly、Secure 的会话 Cookie。

## 目录

    Sources/DshClient/JSONValue.swift  无损 JSON 值
    Sources/DshClient/Wire.swift       RPC 信封 / 错误 / typed 模型
    Sources/DshClient/DshClient.swift  call() + mux/host 事件流
    Sources/dsh-spike/main.swift       CLI 冒烟测试

## iOS App（SwiftUI 客户端）

完整的原生 App，和 web 前端是平等的 peer 客户端。

目录：

    App/DshApp.swift                  入口（@main）
    App/AppModel.swift                根状态：baseURL、会话列表、事件桥、审批/提问
    App/SessionModel.swift            单会话：历史折叠、流式、发送
    App/Models.swift                  会话/消息/审批/提问模型
    App/Views/…                       会话列表、聊天、气泡、输入框、审批/提问卡片、设置

构建与运行（xcodegen 生成工程，不提交 .xcodeproj）：

    xcodegen generate
    open DshApp.xcodeproj              # 在 Xcode 里跑

命令行构建（模拟器）：

    xcodebuild -project DshApp.xcodeproj -scheme DshApp       -destination 'generic/platform=iOS Simulator' build

说明：

- App 默认连 http://127.0.0.1:3080（loopback 豁免 ATS）。
- App 不进行后台网络发现；Server 通过二维码或配对链接明确交给用户，连接后按 Host ID 去重。
- 通过 Tailnet 或公网远程访问时，优先扫描 `dsh-network` 生成的配对二维码；Tailnet
  不做自动发现。手动地址仍用于可信的既有部署。
- DshClient（Sources/DshClient）同时被 SwiftPM 包（CLI spike）和 App 内联编译使用。

## 功能清单

- 会话列表（标题/目录/运行中指示，实时更新）
- 聊天：Markdown 渲染（标题/列表/代码块带复制/GFM 表格）、思考过程折叠、工具调用+结果卡片、流式双通道（正文 + reasoning）
- 统计栏：轮数/步数、LLM/工具耗时、首 token、tok/s、输入/输出 token
- 模型切换（session.models / session.selectModel，含 reasoning effort）
- 目标横幅（进行中/暂停/阻塞/完成 + 轮数）
- 后台任务 + 子代理列表（session/jobs 帧 + subagent.list）
- 审批卡片 + 提问表单（单选/多选）
- 离线/断连提醒：检查 Server 在线状态，并提示扫码、粘贴配对链接或手动添加地址
- 深色模式（语义色自适应）

设计参考：DSH web 客户端的消息/思考/工具/统计呈现逻辑，以及 Pharos 项目的零依赖 Markdown 渲染器与 MarkdownUI 表格样式（交替行 + 描边）。
