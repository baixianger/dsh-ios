import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject private var model: SessionModel
    @State private var showModelPicker = false
    @State private var showWork = false
    @State private var showStats = false
    @State private var editingMessageId: String?
    @State private var editingText = ""
    @State private var showEdit = false
    @State private var noteTarget: String? = nil
    @State private var noteText = ""

    init(model: SessionModel) {
        self.model = model
    }

    private var modelLabel: String {
        var name = model.currentModelName ?? "模型"
        if let m = model.modelGroups.flatMap({ $0.models }).first(where: { $0.id == model.currentModelName }) {
            name = m.name
        }
        if let e = model.currentEffort, !e.isEmpty {
            return name + " · " + effortLabel(e)
        }
        return name
    }

    private var groupedItems: [(id: String, items: [ChatItem])] {
        var result: [(id: String, items: [ChatItem])] = []
        var run: [ChatItem] = []
        for item in model.items {
            if item.role == .tool {
                run.append(item)
            } else {
                if !run.isEmpty {
                    result.append((id: "tools-" + (run.first?.id ?? ""), items: run))
                    run = []
                }
                result.append((id: item.id, items: [item]))
            }
        }
        if !run.isEmpty {
            result.append((id: "tools-" + (run.first?.id ?? ""), items: run))
        }
        return result
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

            GoalCard(model: model)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.isLoading {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
                        }
                        ForEach(groupedItems, id: \.id) { group in
                            if group.items.count == 1, group.items[0].role != .tool {
                                messageRow(group.items[0])
                            } else {
                                ToolCallGroupCard(items: group.items)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: model.items.count) { _, _ in
                    if let last = groupedItems.last {
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

            ComposerView(
                draft: $model.draft,
                isRunning: model.isRunning,
                modelLabel: modelLabel,
                permissionLabel: appModel.permissionPreset.map(permissionName) ?? "权限",
                onOpenModelPicker: { showModelPicker = true },
                onChangePermission: { preset in Task { await appModel.setPermission(preset) } },
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
                Button { showStats = true } label: { circleIcon("info") }
                Menu {
                    Menu("模式") {
                        ForEach(appModel.agentPresets) { p in
                            Button(p.displayName) {
                                Task { await appModel.selectAgentPreset(sessionId: model.sessionId, preset: p.id) }
                            }
                        }
                    }
                    Button { showModelPicker = true } label: { Label("模型", systemImage: "cpu") }
                    Button { showWork = true } label: { Label("工作", systemImage: "briefcase") }
                } label: {
                    circleIcon("ellipsis")
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showModelPicker) { ModelPickerSheet(model: model) }
        .sheet(isPresented: $showWork) { WorkSheet(model: model) }
        .sheet(isPresented: $showStats) { StatsSheet(model: model) }
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
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                Form {
                    TextField("消息", text: $editingText, axis: .vertical)
                        .lineLimit(2...8)
                }
                .navigationTitle("编辑消息")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showEdit = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            if let id = editingMessageId {
                                Task { await model.editMessage(messageId: id, text: editingText) }
                            }
                            showEdit = false
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
        }
    }

    @ViewBuilder
    private func messageRow(_ item: ChatItem) -> some View {
        MessageBubble(
            item: item,
            feedback: model.feedbackByMessage[item.messageId ?? ""],
            onRemoveMessage: { mid in
                Task { await model.removeMessage(messageId: mid) }
            },
            onEditMessage: { mid, text in
                editingMessageId = mid
                editingText = text
                showEdit = true
            },
            onSteerMessage: { mid in
                Task { await model.steerMessage(messageId: mid) }
            },
            onToggleFeedback: { rating in
                if let mid = item.messageId {
                    Task { await model.toggleFeedback(messageId: mid, rating: rating) }
                }
            },
            onEditFeedbackNote: { mid in
                noteTarget = mid
                noteText = model.feedbackByMessage[mid]?.note ?? ""
            }
        )
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .background(Color.dsSurfaceElevated, in: Circle())
            .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
    }
}
