import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject private var model: SessionModel
    @State private var showModelPicker = false
    @State private var showWork = false
    @State private var showStats = false
    @State private var showTrajectory = false
    @State private var noteTarget: String? = nil
    @State private var noteText = ""
    @State private var pendingPermission: String?

    init(model: SessionModel) {
        self.model = model
    }

    private var modelLabel: String {
        var name = model.currentModelName ?? String(localized: "模型")
        let group = model.modelGroups.first { $0.id == model.currentProvider }
        if let selected = group?.models.first(where: { $0.id == model.currentModelName }) {
            name = selected.name
            guard let reasoning = selected.reasoning else { return name }
            let effectiveEffort = model.currentEffort ?? reasoning.defaultEffort
            let effortName = effectiveEffort.flatMap { id in
                reasoning.efforts.first(where: { $0.id == id })?.name ?? effortLabel(id)
            } ?? String(localized: "提供商默认")
            return name + " · " + effortName
        }
        return name
    }

    private var presetLabel: String? {
        guard let id = model.summary?.agentPreset else { return nil }
        return appModel.agentPresets.first(where: { $0.id == id })?.displayName ?? id
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.planActive {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.tint)
                    Text("计划模式")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.dsAccentBlue.opacity(0.12))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if model.isLoading {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
                        }
                        ForEach(model.transcriptEntries) { entry in
                            transcriptRow(for: entry)
                        }
                    }
                    .padding()
                }
                .onChange(of: model.items.count) { _, _ in
                    if let last = model.transcriptEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            let approvals = appModel.pendingApprovals.filter { $0.sessionId == model.sessionId }
            let questions = appModel.pendingQuestions.filter { $0.sessionId == model.sessionId }
            if !approvals.isEmpty || !questions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(approvals) { ApprovalCard(wait: $0) }
                    ForEach(questions) { QuestionCard(wait: $0) }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if !model.jobs.isEmpty || !model.subagents.isEmpty {
                WorkStatusStrip(
                    jobs: model.jobs,
                    subagents: model.subagents,
                    onOpen: { showWork = true }
                )
            }

            GoalCard(model: model)

            if let error = model.commandError {
                Text("命令加载失败：\(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = model.sendError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ComposerView(
                draft: $model.draft,
                isRunning: model.isRunning,
                modelLabel: modelLabel,
                permissionLabel: model.permissionPreset.map(permissionName) ?? appModel.permissionPreset.map(permissionName) ?? String(localized: "权限"),
                commands: model.commands,
                onOpenModelPicker: { showModelPicker = true },
                onChangePermission: { preset in
                    if preset == "danger-full-access" { pendingPermission = preset }
                    else { Task { await model.setPermission(preset) } }
                },
                onSend: { image, text in
                    var imagePart: (data: String, mediaType: String)?
                    if let image, let jpeg = image.jpegData(compressionQuality: 0.8) {
                        imagePart = (data: jpeg.base64EncodedString(), mediaType: "image/jpeg")
                    }
                    Task { await model.send(text, image: imagePart) }
                },
                onStop: { Task { await model.cancel() } })
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle(model.summary?.title ?? "会话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("会话统计", systemImage: "info.circle") {
                    showStats = true
                }
                .labelStyle(.iconOnly)

                Menu {
                    if let preset = presetLabel {
                        Label("模式：\(preset)", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    Button { showModelPicker = true } label: { Label("模型", systemImage: "cpu") }
                    Button { showWork = true } label: { Label("工作", systemImage: "briefcase") }
                    Button { showTrajectory = true } label: { Label("轨迹", systemImage: "point.3.connected.trianglepath.dotted") }
                } label: {
                    Label("更多", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showModelPicker) { ModelPickerSheet(model: model) }
        .sheet(isPresented: $showWork) { WorkSheet(model: model) }
        .sheet(isPresented: $showStats) { StatsSheet(model: model) }
        .sheet(isPresented: $showTrajectory) { TrajectorySheet(model: model) }
        .alert("确认完整访问权限", isPresented: Binding(get: { pendingPermission != nil }, set: { if !$0 { pendingPermission = nil } })) {
            Button("取消", role: .cancel) { pendingPermission = nil }
            Button("确认", role: .destructive) {
                if let preset = pendingPermission { Task { await model.setPermission(preset) } }
                pendingPermission = nil
            }
        } message: {
            Text("完整访问权限允许会话读写工作区外的文件并执行高风险操作。")
        }
        .alert("会话操作失败", isPresented: Binding(get: { model.permissionError != nil }, set: { if !$0 { model.permissionError = nil } })) {
            Button("好", role: .cancel) { model.permissionError = nil }
        } message: { Text(model.permissionError ?? "未知错误") }
        .alert("会话操作失败", isPresented: Binding(get: { model.operationError != nil }, set: { if !$0 { model.operationError = nil } })) {
            Button("好", role: .cancel) { model.operationError = nil }
        } message: { Text(model.operationError ?? "未知错误") }
        .sheet(isPresented: Binding(get: { noteTarget != nil }, set: { if !$0 { noteTarget = nil } })) {
            NavigationStack {
                Form {
                    TextField("这条回答哪里好，或哪里有问题？", text: $noteText, axis: .vertical)
                        .lineLimit(2...6)
                }
                .navigationTitle("反馈说明")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { noteTarget = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            if let mid = noteTarget {
                                Task { await model.setFeedbackNote(messageId: mid, note: noteText) }
                            }
                            noteTarget = nil
                        }
                    }
                }
            }
        }
        .task {
            await model.loadHistory()
            await model.loadModels()
            await model.loadSubagents()
            await model.loadSkills()
            await model.loadFeedback()
            await model.loadCommands()
        }
    }

    private var branchableEntryId: String? {
        model.transcriptEntries.reversed().first { entry in
            guard case .message(let item) = entry else { return false }
            return item.role == .assistant && !item.isStreaming && !item.text.isEmpty
        }?.id
    }

    private func transcriptRow(for entry: TranscriptEntry) -> some View {
        let messageId = entry.message?.messageId
        let feedback = messageId.flatMap { model.feedbackByMessage[$0] }
        let branchAction: (() -> Void)? = entry.id == branchableEntryId
            ? { Task { await appModel.forkSession(sessionId: model.sessionId) } }
            : nil

        return TranscriptRow(
            entry: entry,
            feedback: feedback,
            onToggleFeedback: { messageId, rating in
                Task { await model.toggleFeedback(messageId: messageId, rating: rating) }
            },
            onEditFeedbackNote: { messageId in
                noteTarget = messageId
                noteText = model.feedbackByMessage[messageId]?.note ?? ""
            },
            onBranch: branchAction
        )
    }

}

private struct WorkStatusStrip: View {
    let jobs: [JobView]
    let subagents: [SubagentEntry]
    let onOpen: () -> Void

    private var runningJobs: Int {
        jobs.lazy.filter { $0.status == "running" }.count
    }

    private var activeSubagents: Int {
        subagents.lazy.filter { !$0.isDiagnostic && $0.activity == "running" }.count
    }

    private var availableSubagents: Int {
        subagents.lazy.filter { !$0.isDiagnostic }.count
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if runningJobs > 0 {
                    statusButton(
                        title: "\(runningJobs) 个后台任务",
                        systemImage: "circle.dotted"
                    )
                }
                if availableSubagents > 0 {
                    statusButton(
                        title: activeSubagents > 0
                            ? "\(activeSubagents) 个子代理运行中"
                            : "\(availableSubagents) 个子代理",
                        systemImage: "cpu"
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private func statusButton(title: String, systemImage: String) -> some View {
        Button(action: onOpen) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.14), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

private struct TranscriptRow: View {
    let entry: TranscriptEntry
    let feedback: MessageFeedbackItem?
    let onToggleFeedback: (String, String) -> Void
    let onEditFeedbackNote: (String) -> Void
    let onBranch: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch entry {
            case .message(let item):
                MessageBubble(
                    item: item,
                    feedback: feedback,
                    onToggleFeedback: { rating in
                        guard let messageId = item.messageId else { return }
                        onToggleFeedback(messageId, rating)
                    },
                    onEditFeedbackNote: onEditFeedbackNote,
                    onBranch: onBranch
                )
            case .activity(_, let reasoning, let tools):
                ActivityGroupCard(reasoning: reasoning, tools: tools)
            }
        }
    }
}
