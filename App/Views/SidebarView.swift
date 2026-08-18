import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    let onSelectConversation: (String) -> Void
    let onClose: () -> Void

    @State private var creatingProject = false
    @State private var newProjectPath = ""
    @State private var renameTarget: Workspace?
    @State private var renameSessionTarget: SessionSummary?
    @State private var renameServerTarget: DshServer?
    @State private var query = ""
    @State private var showsSearch = false
    @State private var expandedWorkspaceIds: Set<String> = []
    @State private var grouping: Grouping = .grouped
    @State private var ordering: Ordering = .lastUpdated
    @State private var deleteTarget: Workspace?
    @State private var mutationError: String?
    @State private var mutationPending = false
    @State private var createProjectError: String?
    @State private var createProjectPending = false

    private enum Grouping: String { case grouped, flat }
    private enum Ordering: String { case manual, lastUpdated }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    model.showWelcome()
                    onClose()
                } label: {
                    DSHBrandTitle()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("DeepSeek Harness 首页")
                Spacer()
            }
            .frame(height: 44)
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .padding(.top, 1)

            if showsSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索会话", text: $query)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.dsSurfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !query.isEmpty {
                        sectionTitle("搜索结果")
                        if searchResults.isEmpty {
                            emptyRow("没有匹配的会话")
                        } else {
                            ForEach(searchResults) { session in
                                sessionRow(
                                    session,
                                    subtitle: projectTitle(for: session.sessionId)
                                )
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            if let server = sidebarSnapshots.first?.server {
                                hostSectionTitle(server)
                            } else {
                                sectionTitle(String(localized: "工作区"))
                            }
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    showsSearch.toggle()
                                }
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.subheadline.weight(.medium))
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showsSearch ? "关闭搜索" : "搜索会话")

                            Menu {
                                Picker("分组", selection: $grouping) {
                                    Text("按工作区分组").tag(Grouping.grouped)
                                    Text("全部会话").tag(Grouping.flat)
                                }
                                Picker("排序", selection: $ordering) {
                                    Text("手动顺序").tag(Ordering.manual)
                                    Text("最近更新").tag(Ordering.lastUpdated)
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.subheadline.weight(.medium))
                                    .frame(width: 32, height: 32)
                            }
                            .menuStyle(.automatic)
                            .accessibilityLabel("视图选项")

                            Button {
                                creatingProject = true
                            } label: {
                                Image("DSHProjectAdd")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 17, height: 17)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("添加工作区")
                        }

                        if model.isLoadingSessions && sidebarSnapshots.isEmpty {
                            ProgressView("加载…")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 16)
                        } else if sidebarSnapshots.isEmpty {
                            if model.isOffline {
                                OfflineReminderView()
                                    .padding(.vertical, 8)
                            } else {
                                emptyRow("暂无工作区")
                            }
                        } else {
                            ForEach(Array(sidebarSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                                if index > 0 {
                                    hostSectionTitle(snapshot.server)
                                }
                                if grouping == .grouped {
                                    ForEach(snapshot.workspaces) { workspace in
                                        workspaceSection(workspace, snapshot: snapshot)
                                    }
                                } else {
                                    ForEach(flatSessions(in: snapshot)) { session in
                                        sessionRow(
                                            session,
                                            subtitle: projectTitle(for: session.sessionId, in: snapshot),
                                            serverID: snapshot.server.id,
                                            workspaceID: snapshot.workspaces.first(where: { $0.sessionIds.contains(session.sessionId) })?.workspaceId
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .refreshable {
                await model.loadSessions()
                await model.loadWorkspaces()
            }
        }
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    model.requestNewChatDestination()
                } label: {
                    Label("新建聊天", systemImage: "square.and.pencil")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.dsAccentBlue, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    model.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3.weight(.medium))
                        .frame(width: 52, height: 52)
                        .background(.thinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.secondary.opacity(0.14), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("设置")
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $creatingProject) { createProjectSheet }
        .sheet(item: $renameTarget) { target in
            RenameEntitySheet(title: "重命名工作区", fieldLabel: "名称", initialValue: target.title) { value in
                try await model.renameWorkspace(workspaceId: target.workspaceId, title: value)
            }
        }
        .sheet(item: $renameSessionTarget) { target in
            RenameEntitySheet(
                title: "重命名会话",
                fieldLabel: "标题",
                initialValue: target.title ?? ""
            ) { value in
                try await model.renameSession(sessionId: target.sessionId, title: value)
            }
        }
        .sheet(item: $renameServerTarget) { server in
            RenameEntitySheet(
                title: "设置 Host 别名",
                fieldLabel: "别名",
                initialValue: server.displayName
            ) { value in
                model.setServerAlias(serverID: server.id, alias: value)
            }
        }
        .alert("删除工作区？", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("删除", role: .destructive) {
                guard let target = deleteTarget else { return }
                mutationPending = true
                Task {
                    do {
                        try await model.deleteWorkspace(workspaceId: target.workspaceId)
                        deleteTarget = nil
                    }
                    catch { mutationError = error.localizedDescription }
                    mutationPending = false
                }
            }
            .disabled(mutationPending)
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("工作区将被删除，其中的会话会回到未分组区域。此操作不可撤销。")
        }
        .alert("操作失败", isPresented: Binding(get: { mutationError != nil }, set: { if !$0 { mutationError = nil } })) {
            Button("好", role: .cancel) { mutationError = nil }
        } message: {
            Text(mutationError ?? "未知错误")
        }
    }

    private var searchResults: [SessionSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return model.sessions
            .filter { !$0.blank && !model.archivedSessionIds.contains($0.sessionId) }
            .filter { ($0.title ?? "").localizedCaseInsensitiveContains(q) || ($0.cwd ?? "").localizedCaseInsensitiveContains(q) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var sidebarSnapshots: [ServerWorkspaceSnapshot] {
        if !model.sidebarServers.isEmpty { return model.sidebarServers }
        guard !model.isOffline, let server = model.activeServer else { return [] }
        return [ServerWorkspaceSnapshot(
            server: server,
            workspaces: model.workspaces,
            sessions: model.sessions,
            archivedSessionIds: model.archivedSessionIds
        )]
    }

    private func projectTitle(for sessionId: String) -> String? {
        model.workspaces.first(where: { $0.sessionIds.contains(sessionId) })?.title
    }

    private func projectTitle(for sessionId: String, in snapshot: ServerWorkspaceSnapshot) -> String? {
        snapshot.workspaces.first(where: { $0.sessionIds.contains(sessionId) })?.title
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.top, 18)
            .padding(.bottom, 10)
    }

    private func hostSectionTitle(_ server: DshServer) -> some View {
        sectionTitle(server.displayName)
            .contextMenu {
                Button("设置 Host 别名", systemImage: "pencil") {
                    renameServerTarget = server
                }
                if server.alias != nil {
                    Button("清除别名", systemImage: "arrow.uturn.backward") {
                        model.setServerAlias(serverID: server.id, alias: nil)
                    }
                }
            }
            .accessibilityAction(named: "设置 Host 别名") {
                renameServerTarget = server
            }
    }

    private func emptyRow(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }

    private func workspaceSection(_ workspace: Workspace, snapshot: ServerWorkspaceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let sessions = conversations(in: workspace, snapshot: snapshot)
            let expansionID = "\(snapshot.server.id.uuidString):\(workspace.workspaceId)"
            let isExpanded = expandedWorkspaceIds.contains(expansionID)
            let isCurrentServer = model.activeServerID == snapshot.server.id
            let isActive = isCurrentServer && isExpanded && model.selectedWorkspaceId == workspace.workspaceId

            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isExpanded {
                            expandedWorkspaceIds.remove(expansionID)
                        } else {
                            expandedWorkspaceIds.insert(expansionID)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(isExpanded ? "DSHFolderOpen" : "DSHFolderClosed")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(isActive ? Color.dsAccentBlue : Color.primary)
                        Text(workspace.title)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isCurrentServer {
                    Menu {
                        Button("新建会话", systemImage: "square.and.pencil") {
                            model.newChat(workspaceId: workspace.workspaceId)
                            onClose()
                        }
                        Button("重命名", systemImage: "pencil") {
                            renameTarget = workspace
                        }
                        Button("删除", systemImage: "trash", role: .destructive) {
                            deleteTarget = workspace
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(workspace.title) 工作区操作")
                }
            }
            .frame(height: 34)
            .padding(.top, 8)

            if sessions.isEmpty {
                EmptyView()
            } else {
                let visibleSessions = isExpanded ? sessions : Array(sessions.prefix(3))

                ForEach(visibleSessions) { session in
                    sessionRow(
                        session,
                        serverID: snapshot.server.id,
                        workspaceID: workspace.workspaceId
                    )
                }

                if sessions.count > 3 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded {
                                expandedWorkspaceIds.remove(expansionID)
                            } else {
                                expandedWorkspaceIds.insert(expansionID)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "收起 \(workspace.title) 的聊天" : "展开 \(workspace.title) 的其余 \(sessions.count - 3) 个聊天")
                }
            }
        }
    }

    private func sessionRow(
        _ s: SessionSummary,
        subtitle: String? = nil,
        serverID: UUID? = nil,
        workspaceID: String? = nil
    ) -> some View {
        let targetServerID = serverID ?? model.activeServerID
        let isCurrentServer = targetServerID == model.activeServerID
        return Button {
            if let targetServerID {
                model.openSidebarSession(serverID: targetServerID, workspaceID: workspaceID, sessionID: s.sessionId)
                onClose()
            } else {
                onSelectConversation(s.sessionId)
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title ?? String(localized: s.blank ? "新会话" : "未命名"))
                        .font(.subheadline)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if s.running { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: subtitle == nil ? 32 : 40)
            .background(
                isCurrentServer && model.selectedConversationId == s.sessionId
                    ? Color.dsSurfaceSelected
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isCurrentServer {
                Button("重命名", systemImage: "pencil") {
                    renameSessionTarget = s
                }
                Button("分支", systemImage: "arrow.branch") {
                    Task { await model.forkSession(sessionId: s.sessionId) }
                }
                Button("归档", systemImage: "archivebox", role: .destructive) {
                    Task {
                        do { try await model.archiveSession(sessionId: s.sessionId) }
                        catch { mutationError = error.localizedDescription }
                    }
                }
            }
        }
    }

    private func conversations(in workspace: Workspace, snapshot: ServerWorkspaceSnapshot) -> [SessionSummary] {
        let visible = snapshot.sessions.filter {
            workspace.sessionIds.contains($0.sessionId) && !$0.blank && !snapshot.archivedSessionIds.contains($0.sessionId)
        }
        if ordering == .lastUpdated { return visible.sorted { $0.updatedAt > $1.updatedAt } }
        return workspace.sessionIds.compactMap { id in visible.first { $0.sessionId == id } }
    }

    private func flatSessions(in snapshot: ServerWorkspaceSnapshot) -> [SessionSummary] {
        let visible = snapshot.sessions.filter { !$0.blank && !snapshot.archivedSessionIds.contains($0.sessionId) }
        if ordering == .lastUpdated { return visible.sorted { $0.updatedAt > $1.updatedAt } }
        var seen = Set<String>()
        var result: [SessionSummary] = []
        for ws in snapshot.workspaces {
            for id in ws.sessionIds where !seen.contains(id) {
                if let session = visible.first(where: { $0.sessionId == id }) {
                    seen.insert(id)
                    result.append(session)
                }
            }
        }
        // Sessions not present in any workspace are the truthful flat-view
        // equivalent of Web's Ungrouped section.
        result.append(contentsOf: visible.filter { !seen.contains($0.sessionId) })
        return result
    }

    private var createProjectSheet: some View {
        NavigationStack {
            Form {
                Section("工作区路径") {
                    TextField("/path/to/project", text: $newProjectPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("输入一个已存在的目录路径，将其纳为工作区。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let createProjectError {
                    Section {
                        Text(createProjectError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("新建工作区")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { creatingProject = false }
                        .disabled(createProjectPending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        let p = newProjectPath.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !p.isEmpty else { return }
                        createProjectPending = true
                        createProjectError = nil
                        Task {
                            do {
                                _ = try await model.addWorkspace(path: p)
                                newProjectPath = ""
                                creatingProject = false
                            } catch {
                                createProjectError = error.localizedDescription
                            }
                            createProjectPending = false
                        }
                    }
                    .disabled(createProjectPending || newProjectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(createProjectPending)
        }
    }
}

private struct RenameEntitySheet: View {
    let title: LocalizedStringKey
    let fieldLabel: LocalizedStringKey
    let action: @MainActor (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        title: LocalizedStringKey,
        fieldLabel: LocalizedStringKey,
        initialValue: String,
        action: @escaping @MainActor (String) async throws -> Void
    ) {
        self.title = title
        self.fieldLabel = fieldLabel
        self.action = action
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(fieldLabel, text: $value)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        isSaving = true
                        errorMessage = nil
                        Task {
                            do {
                                try await action(trimmed)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                isSaving = false
                            }
                        }
                    }
                    .disabled(isSaving || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
        .presentationDetents([.medium])
    }
}
