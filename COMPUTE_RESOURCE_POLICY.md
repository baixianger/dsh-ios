# DSH iOS 构建与验证资源策略

## 机器分工

- 当前工作电脑：只用于代码编辑、文档、差异检查和必要的轻量静态检查。默认不得在这里启动 iPhone/iPad Simulator，也不得并行执行多个 Xcode 构建。
- Mac mini：作为模拟器构建与 UI 验证主机，通过 SSH 别名 `mac-mini` 连接，项目位置为 `/Users/baixianger/personal/dsh-ios`。
- 实体设备安装必须在设备实际连接的机器上执行；不得为了安装而同时保留本地模拟器。

## 远端工作保护

- Mac mini 的项目工作树可能包含其他 Agent 或用户的未提交修改。每次操作前必须运行 `git status --short`，不得使用 reset、checkout、clean 或直接 rsync 覆盖该工作树。
- 本机内容需要远端验证时，应同步到独立临时目录或专用 worktree；不要复用或改写 `/Users/baixianger/personal/dsh-ios` 中的现有修改。
- 验证结果、截图和层级文件应写入独立证据目录，并把绝对路径写回 `HANDOFF.md`。

## 内存与并发限制

- 任意一台机器同一时间最多运行 1 台 Simulator。
- 优先复用已存在的目标设备；开始前检查 Booted 设备和内存状态。
- 不同时运行 iPhone 与 iPad 验证。按“构建一次 → 单设备验证 → 关机 → 下一设备”的顺序执行。
- 每个设备验证完成后 terminate App；整轮完成后 shutdown Simulator。
- Mac mini 已经有其他 Booted Simulator 时，不得擅自关闭可能属于其他任务的设备；先确认占用来源，或等待资源释放。

## 默认验证顺序

1. 本机完成代码与文档修改，不启动 Simulator。
2. 只读检查 Mac mini 的工作树、Booted 设备和内存。
3. 把待验证版本放入隔离目录。
4. Mac mini 上一次只启动一个目标：优先 iPhone 竖屏，其次横屏，最后 iPad。
5. 收集 screenshot、UI hierarchy 和交互结果。
6. 关闭远端 Simulator，并把结果同步回本机。

