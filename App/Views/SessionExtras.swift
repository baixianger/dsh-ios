import SwiftUI

// MARK: - Stats bar (borrowed from DSH web stats presentation)

struct StatsBar: View {
    @ObservedObject var model: SessionModel

    var body: some View {
        let line = Self.line(model.stats, tokenUsage: model.tokenUsage)
        if !line.isEmpty {
            Text(line)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.bar)
        }
    }

    static func line(_ stats: JSONValue?, tokenUsage: JSONValue?) -> String {
        guard let stats else { return "" }
        let turns = stats["turns"]?.double ?? 0
        let steps = stats["steps"]?.double ?? 0
        let llmMs = stats["llmMs"]?.double ?? 0
        let toolMs = stats["toolMs"]?.double ?? 0
        let ttftMs = stats["ttftMs"]?.double ?? 0
        let ttftSteps = stats["ttftSteps"]?.double ?? 0
        let decodeMs = stats["decodeMs"]?.double ?? 0
        let decodeTokens = stats["decodeTokens"]?.double ?? 0
        let input = tokenUsage?["uncachedInputTokens"]?.double ?? 0
        let output = tokenUsage?["outputTokens"]?.double ?? 0

        var parts: [String] = []
        if turns > 0 || steps > 0 { parts.append("\(Int(turns)) 轮 · \(Int(steps)) 步") }
        if llmMs > 0 { parts.append("LLM " + fmt(ms: llmMs)) }
        if toolMs > 0 { parts.append("工具 " + fmt(ms: toolMs)) }
        if ttftSteps > 0 { parts.append("首token " + fmt(ms: ttftMs / ttftSteps)) }
        if decodeMs > 0 && decodeTokens > 0 { parts.append(String(format: "%.1f tok/s", decodeTokens / (decodeMs / 1000))) }
        if input > 0 || output > 0 { parts.append("入 " + fmtTok(input) + " · 出 " + fmtTok(output)) }
        return parts.joined(separator: " · ")
    }

    private static func fmt(ms: Double) -> String {
        if ms < 1000 { return String(format: "%.0fms", ms) }
        if ms < 60000 { return String(format: "%.1fs", ms / 1000) }
        return String(format: "%.1fm", ms / 60000)
    }

    private static func fmtTok(_ n: Double) -> String {
        if n >= 1000 { return String(format: "%.1fK", n / 1000) }
        return String(format: "%.0f", n)
    }
}

// MARK: - Goal card (create / edit / pause / resume / complete / clear)

struct GoalCard: View {
    @ObservedObject var model: SessionModel
    @State private var showEditor = false
    @State private var expanded = false

    var body: some View {
        if let goal = model.goal {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: phaseIcon(goal.phase))
                            .foregroundStyle(phaseColor(goal.phase))
                        Text(phaseLabel(goal.phase))
                            .font(.caption.weight(.semibold))
                        Text(goal.objective)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if goal.maxGoalRounds > 0 {
                            Text("\(Int(goal.roundsStarted))/\(Int(goal.maxGoalRounds))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: expanded ? "chevron.down" : "chevron.up")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("目标，\(phaseLabel(goal.phase))，\(goal.objective)")
                .accessibilityValue(goal.maxGoalRounds > 0 ? "第 \(Int(goal.roundsStarted)) 轮，共 \(Int(goal.maxGoalRounds)) 轮" : "")

                if expanded {
                    Divider()
                        .padding(.horizontal, 12)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(goal.objective)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)

                        if goal.maxGoalRounds > 0 {
                            ProgressView(
                                value: Double(min(goal.roundsStarted, goal.maxGoalRounds)),
                                total: Double(goal.maxGoalRounds)
                            )
                            .tint(.accentColor)
                        }

                        if let blocked = goal.blockedReason, !blocked.isEmpty {
                            Label(blocked, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        HStack(spacing: 8) {
                            Button("编辑", systemImage: "pencil") { showEditor = true }
                            if goal.phase == "active" {
                                Button("暂停") { Task { await model.pauseGoal() } }
                            } else if goal.phase == "paused" {
                                Button("恢复") { Task { await model.resumeGoal() } }
                            }
                            if goal.phase != "complete" {
                                Button("完成") { Task { await model.completeGoal() } }
                            }
                            Spacer()
                            Button("清除", systemImage: "trash", role: .destructive) {
                                Task { await model.clearGoal() }
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                    .padding(12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .sheet(isPresented: $showEditor) {
                GoalEditorSheet(model: model, editing: goal)
            }
        } else {
            Button {
                showEditor = true
            } label: {
                Label("设定目标", systemImage: "target")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.14), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .sheet(isPresented: $showEditor) {
                GoalEditorSheet(model: model, editing: nil)
            }
        }
    }

    private func phaseLabel(_ phase: String) -> String {
        switch phase {
        case "active": return "正在推进"
        case "paused": return "已暂停"
        case "blocked": return "已阻塞"
        case "complete": return "已完成"
        default: return phase
        }
    }

    private func phaseColor(_ phase: String) -> Color {
        switch phase {
        case "active": return .green
        case "paused": return .orange
        case "blocked": return .red
        case "complete": return .blue
        default: return .secondary
        }
    }

    private func phaseIcon(_ phase: String) -> String {
        switch phase {
        case "active": return "target"
        case "paused": return "pause.circle"
        case "blocked": return "exclamationmark.triangle"
        case "complete": return "checkmark.circle"
        default: return "target"
        }
    }
}

struct GoalEditorSheet: View {
    @ObservedObject var model: SessionModel
    let editing: GoalState?
    @Environment(\.dismiss) private var dismiss
    @State private var objective = ""
    @State private var maxRounds = 5.0

    var body: some View {
        NavigationStack {
            Form {
                Section("目标描述") {
                    TextField("目标", text: $objective, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section("最大自动轮数") {
                    Stepper("\(Int(maxRounds)) 轮", value: $maxRounds, in: 1...100)
                }
            }
            .navigationTitle(editing == nil ? "新建目标" : "编辑目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let obj = objective.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !obj.isEmpty else { return }
                        Task {
                            if editing != nil {
                                await model.editGoal(objective: obj, maxGoalRounds: Int(maxRounds))
                            } else {
                                await model.createGoal(objective: obj, maxGoalRounds: Int(maxRounds))
                            }
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let editing {
                    objective = editing.objective
                    maxRounds = Double(editing.maxGoalRounds > 0 ? editing.maxGoalRounds : 5)
                }
            }
        }
    }
}

// MARK: - Read / diff cards

struct ReadCardView: View {
    let card: ReadCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").font(.caption).foregroundStyle(.secondary)
                Text(card.label).font(.caption.weight(.medium)).lineLimit(1)
                Spacer()
                if let lang = card.lang, !lang.isEmpty {
                    Text(lang)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(line.number.map { String(Int($0)) } ?? "")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(minWidth: 28, alignment: .trailing)
                            Text(line.text)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let total = card.totalLines, total > Double(card.lines.count) {
                Text("显示 \(card.lines.count) / \(Int(total)) 行")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
            }
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
    }
}

struct DiffCardView: View {
    let card: DiffCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(card.diffs.enumerated()), id: \.offset) { _, hunk in
                VStack(alignment: .leading, spacing: 2) {
                    Text(hunk.path).font(.caption.weight(.medium)).lineLimit(1)
                    if let old = hunk.oldText, !old.isEmpty {
                        Text(old).font(.caption.monospaced()).foregroundStyle(.red.opacity(0.8)).textSelection(.enabled)
                    }
                    Text(hunk.newText).font(.caption.monospaced()).foregroundStyle(.green.opacity(0.8)).textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
    }
}

// MARK: - Model picker sheet

func effortLabel(_ id: String) -> String {
    switch id {
    case "off": return "关闭"
    case "high": return "高"
    case "max": return "最高"
    default: return id
    }
}

func permissionName(_ preset: String) -> String {
    switch preset {
    case "read-only": return "只读"
    case "workspace-write": return "可写"
    case "danger-full-access": return "完全访问"
    default: return preset
    }
}

struct ModelPickerSheet: View {
    @ObservedObject var model: SessionModel
    @Environment(\.dismiss) private var dismiss
    @State private var provider = ""
    @State private var modelId = ""
    @State private var effort = ""

    private var selectedModel: ModelInfo? {
        model.modelGroups.first(where: { $0.id == provider })?.models.first(where: { $0.id == modelId })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("模型") {
                    ForEach(model.modelGroups) { group in
                        ForEach(group.models) { m in
                            Button {
                                provider = group.id
                                modelId = m.id
                                // Match DSH Web: choosing a model adopts that exact
                                // model's declared default. No reasoning metadata means
                                // no synthetic effort is submitted.
                                effort = m.reasoning?.defaultEffort ?? ""
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(m.name).foregroundStyle(.primary)
                                        Text(group.name).font(.caption2).foregroundStyle(.secondary)
                                        if let description = m.description, !description.isEmpty {
                                            Text(description)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    if provider == group.id && modelId == m.id {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }

                if let reasoning = selectedModel?.reasoning {
                    Section("思考强度") {
                        Picker("思考", selection: $effort) {
                            if reasoning.defaultEffort == nil {
                                Text("提供商默认").tag("")
                            }
                            ForEach(reasoning.efforts) { level in
                                Text(level.name).tag(level.id)
                            }
                        }
                        .pickerStyle(.navigationLink)

                        if let selected = reasoning.efforts.first(where: { $0.id == effort }),
                           let description = selected.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        Task {
                            await model.selectModel(provider: provider, model: modelId, effort: effort.isEmpty ? nil : effort)
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                provider = model.currentProvider ?? model.modelGroups.first?.id ?? ""
                modelId = model.currentModelName ?? model.modelGroups.first?.models.first?.id ?? ""
                let currentModel = model.modelGroups
                    .first(where: { $0.id == provider })?
                    .models.first(where: { $0.id == modelId })
                effort = model.currentEffort ?? currentModel?.reasoning?.defaultEffort ?? ""
            }
        }
    }
}

struct StatsSheet: View {
    @ObservedObject var model: SessionModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let stats = model.stats {
                    Section("会话") {
                        row("轮数", Int(stats["turns"]?.double ?? 0))
                        row("步骤", Int(stats["steps"]?.double ?? 0))
                    }
                    Section("耗时") {
                        row("LLM", fmtMs(stats["llmMs"]?.double ?? 0))
                        row("工具", fmtMs(stats["toolMs"]?.double ?? 0))
                        let ttft = stats["ttftMs"]?.double ?? 0
                        let ttftSteps = stats["ttftSteps"]?.double ?? 0
                        if ttftSteps > 0 { row("平均首 token", fmtMs(ttft / ttftSteps)) }
                        let decodeMs = stats["decodeMs"]?.double ?? 0
                        let decodeTokens = stats["decodeTokens"]?.double ?? 0
                        if decodeMs > 0 && decodeTokens > 0 {
                            row("生成速度", String(format: "%.1f tok/s", decodeTokens / (decodeMs / 1000)))
                        }
                    }
                }
                if let t = model.tokenUsage {
                    Section("令牌") {
                        row("输入", fmtTok(t["uncachedInputTokens"]?.double ?? 0))
                        row("输出", fmtTok(t["outputTokens"]?.double ?? 0))
                        row("缓存读取", fmtTok(t["cacheReadTokens"]?.double ?? 0))
                        row("缓存写入", fmtTok(t["cacheWriteTokens"]?.double ?? 0))
                        let read = t["cacheReadTokens"]?.double ?? 0
                        let uncached = t["uncachedInputTokens"]?.double ?? 0
                        if read + uncached > 0 {
                            row("缓存命中率", String(format: "%.1f%%", read / (read + uncached) * 100))
                        }
                    }
                }
                if model.stats == nil && model.tokenUsage == nil {
                    Text("暂无统计数据").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("会话统计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
    }

    private func row(_ label: String, _ value: Int) -> some View { row(label, String(value)) }
    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value) }
    }
    private func fmtMs(_ ms: Double) -> String {
        if ms < 1000 { return String(format: "%.0fms", ms) }
        if ms < 60000 { return String(format: "%.1fs", ms / 1000) }
        return String(format: "%.1fm", ms / 60000)
    }
    private func fmtTok(_ n: Double) -> String {
        if n >= 1000 { return String(format: "%.1fK", n / 1000) }
        return String(format: "%.0f", n)
    }
}

// MARK: - Work sheet (jobs + subagents)

struct WorkSheet: View {
    @ObservedObject var model: SessionModel
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var showExport = false
    @State private var promptTarget: SubagentEntry?
    @State private var promptText = ""
    @State private var viewingSubagent: SubagentEntry?

    var body: some View {
        NavigationStack {
            List {
                Section("会话") {
                    Button {
                        Task {
                            exportURL = await model.export()
                            showExport = exportURL != nil
                        }
                    } label: {
                        Label("导出会话日志", systemImage: "square.and.arrow.up")
                    }
                }

                Section("后台任务") {
                    if model.jobs.isEmpty {
                        Text("无").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.jobs) { job in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.label).font(.subheadline)
                                    if let d = job.detail {
                                        Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                                Spacer()
                                jobStatus(job.status)
                            }
                        }
                    }
                }
                Section("技能") {
                    if model.skills.isEmpty {
                        Text("无").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.skills) { s in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.subheadline)
                                if !s.description.isEmpty {
                                    Text(s.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("子代理") {
                    if model.subagents.isEmpty {
                        Text("无").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.subagents) { sub in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sub.label ?? sub.id).font(.subheadline).lineLimit(1)
                                    Text(sub.isDiagnostic ? (sub.reason ?? "不可用") : sub.mode)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if sub.activity == "running" {
                                    ProgressView().controlSize(.small)
                                }
                            }
                            .contextMenu {
                                if !sub.isDiagnostic {
                                    Button("查看转写", systemImage: "doc.text") {
                                        viewingSubagent = sub
                                    }
                                }
                                if sub.mode == "continuable" {
                                    Button("发消息", systemImage: "paperplane") {
                                        promptText = ""
                                        promptTarget = sub
                                    }
                                    if sub.activity == "running" {
                                        Button("中断", systemImage: "stop.fill", role: .destructive) {
                                            Task { await model.interruptSubagent(childSessionId: sub.id) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("工作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("给子代理发消息", isPresented: Binding(get: { promptTarget != nil }, set: { if !$0 { promptTarget = nil } })) {
                TextField("消息", text: $promptText)
                Button("发送") {
                    if let t = promptTarget {
                        Task { await model.promptSubagent(childSessionId: t.id, text: promptText) }
                    }
                    promptTarget = nil
                }
                Button("取消", role: .cancel) { promptTarget = nil }
            }
            .sheet(item: $viewingSubagent) { sub in
                SubagentHistoryView(model: model, subagentId: sub.id, mode: sub.mode)
            }
            .sheet(isPresented: $showExport) {
                if let url = exportURL {
                    NavigationStack {
                        VStack(spacing: 16) {
                            ShareLink(item: url) {
                                Label("分享会话日志", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.dsAccentBlue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .foregroundStyle(.white)
                            }
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .navigationTitle("导出")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { showExport = false }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func jobStatus(_ s: String) -> some View {
        switch s {
        case "running": ProgressView().controlSize(.small)
        case "completed": Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case "failed": Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case "killed": Image(systemName: "stop.circle.fill").foregroundStyle(.orange)
        default: Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }
}

struct SubagentHistoryView: View {
    @ObservedObject var model: SessionModel
    let subagentId: String
    let mode: String
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ChatItem] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if items.isEmpty {
                        ContentUnavailableView("暂无内容", systemImage: "doc.text")
                    } else {
                        ForEach(items) { item in
                            MessageBubble(item: item)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("子代理转写")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                if let h = await model.loadSubagentHistory(childSessionId: subagentId, mode: mode) {
                    items = h
                }
            }
        }
    }
}

// MARK: - Offline connection reminder

struct OfflineReminderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text("无法连接到 DeepSeek Harness")
                .font(.headline)
            Text("请确认 DSH Server 正在运行，并且本 iPhone 可以访问它的地址。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                step(1, "确认运行 DSH 的主机（Mac / 服务器）在线")
                step(2, "在 Server 上生成二维码，或粘贴一次性配对链接")
                step(3, "Tailnet 或其他网络也可在「设置」中手动添加可访问的 Base URL")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button {
                    Task { await model.loadSessions() }
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    model.showSettings = true
                } label: {
                    Label("打开设置", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.tint)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.14), in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
