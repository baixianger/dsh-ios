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

## iPhone 通过 Tailscale 连

1. 服务器（Mac）上把 3080 安全地暴露到 tailnet。DSH 官方禁止 --host 0.0.0.0，
   所以用 Tailscale 反向代理，而不是改 DSH 绑定：

    tailscale serve --bg https / http://127.0.0.1:3080

   （或者 Caddy/nginx 反代 + 自签 TLS + Bearer token。记住：/api 本身零鉴权，
   只靠 loopback 兜底，绝不能裸暴露。）

2. 告诉 DSH 信任 tailnet 域名（原生客户端不带 Origin 头，靠 Host 过信任检查）：

    dsh --profile web --trusted-host <你的 tailnet 域名或 host:port>

3. 把 iOS App 的 baseURL 指向 https://<tailnet-域名>（wss 事件流自动走 443）。

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
- 远程访问时在「设置」里把 Base URL 改成 https://<tailnet 域名>（走 tailscale serve 的 HTTPS），
  服务器需加 --trusted-host。
- DshClient（Sources/DshClient）同时被 SwiftPM 包（CLI spike）和 App 内联编译使用。

## 功能清单

- 会话列表（标题/目录/运行中指示，实时更新）
- 聊天：Markdown 渲染（标题/列表/代码块带复制/GFM 表格）、思考过程折叠、工具调用+结果卡片、流式双通道（正文 + reasoning）
- 统计栏：轮数/步数、LLM/工具耗时、首 token、tok/s、输入/输出 token
- 模型切换（session.models / session.selectModel，含 reasoning effort）
- 目标横幅（进行中/暂停/阻塞/完成 + 轮数）
- 后台任务 + 子代理列表（session/jobs 帧 + subagent.list）
- 审批卡片 + 提问表单（单选/多选）
- 离线/断连提醒：提示在 DSH 主机与 iPhone 两端安装并登录 Tailscale，一键跳转设置
- 深色模式（语义色自适应）

设计参考：DSH web 客户端的消息/思考/工具/统计呈现逻辑，以及 Pharos 项目的零依赖 Markdown 渲染器与 MarkdownUI 表格样式（交替行 + 描边）。

