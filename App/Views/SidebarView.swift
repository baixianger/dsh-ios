import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    let onSelectConversation: (String) -> Void

    @State private var creatingProject = false
    @State private var newProjectPath = ""
    @State private var renameTarget: Workspace?
    @State private var renameText = ""
    @State private var renameSessionTarget: SessionSummary?
    @State private var renameSessionText = ""
    @State private var query = ""

    var body: some View {
        List {
            Section {
                Button {
                    Task { await model.newChat() }
                } label: {
                    Label("新建会话", systemImage: "square.and.pencil")
                        .font(.body.weight(.semibold))
                }
            }

            Section {
                TextField("搜索会话", text: $query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()

                Button { creatingProject = true } label: {
                    Label("添加项目", systemImage: "folder.badge.plus")
                }
            } header: {
                Text("工作区")
            }

            if !query.isEmpty {
                Section {
                    if searchResults.isEmpty {
                        Text("没有匹配的会话").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(searchResults) { s in
                            sessionRow(s, subtitle: projectTitle(for: s.sessionId), indent: false)
                        }
                    }
                } header: {
                    Text("搜索结果")
                }
            } else if model.isLoadingSessions && model.workspaces.isEmpty {
                Section {
                    ProgressView("加载…")
                }
            } else if model.workspaces.isEmpty {
                Section {
                    if model.isOffline {
                        OfflineReminderView()
                    } else {
                        Text("暂无项目").foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(model.workspaces) { ws in
                    Section {
                        let sessions = model.conversations(in: ws.workspaceId)
                        if sessions.isEmpty {
                            Text("暂无会话").font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(sessions) { s in
                                sessionRow(s)
                            }
                        }
                    } header: {
                        HStack {
                            Text(ws.title).textCase(nil)
                            Spacer()
                            Menu {
                                Button("新建会话", systemImage: "square.and.pencil") {
                                    Task { await model.createSession(workspaceId: ws.workspaceId, agentPreset: nil) }
                                }
                                Button("重命名", systemImage: "pencil") {
                                    renameText = ws.title
                                    renameTarget = ws
                                }
                                Button("删除", systemImage: "trash", role: .destructive) {
                                    Task { await model.deleteWorkspace(workspaceId: ws.workspaceId) }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section {
                Button { model.showSettings = true } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
        .listStyle(.sidebar)
        .refreshable {
            await model.loadSessions()
            await model.loadWorkspaces()
        }
        .sheet(isPresented: $creatingProject) { createProjectSheet }
        .alert("重命名项目", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("名称", text: $renameText)
            Button("保存") {
                if let t = renameTarget {
                    Task { await model.renameWorkspace(workspaceId: t.workspaceId, title: renameText) }
                }
                renameTarget = nil
            }
            Button("取消", role: .cancel) { renameTarget = nil }
        }
        .alert("重命名会话", isPresented: Binding(get: { renameSessionTarget != nil }, set: { if !$0 { renameSessionTarget = nil } })) {
            TextField("标题", text: $renameSessionText)
            Button("保存") {
                if let t = renameSessionTarget {
                    Task { await model.renameSession(sessionId: t.sessionId, title: renameSessionText) }
                }
                renameSessionTarget = nil
            }
            Button("取消", role: .cancel) { renameSessionTarget = nil }
        }
    }

    private var searchResults: [SessionSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return model.sessions
            .filter { ($0.title ?? "").localizedCaseInsensitiveContains(q) || ($0.cwd ?? "").localizedCaseInsensitiveContains(q) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func projectTitle(for sessionId: String) -> String? {
        model.workspaces.first(where: { $0.sessionIds.contains(sessionId) })?.title
    }

    private func sessionRow(_ s: SessionSummary, subtitle: String? = nil, indent: Bool = true) -> some View {
        Button {
            onSelectConversation(s.sessionId)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(s.title ?? (s.blank ? "新会话" : "未命名"))
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    if s.running { ProgressView().controlSize(.mini) }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.leading, indent ? 12 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(model.selectedConversationId == s.sessionId ? Color.dsSurfaceSelected : nil)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await model.archiveSession(sessionId: s.sessionId) }
            } label: { Label("归档", systemImage: "archivebox") }
        }
        .contextMenu {
            Button("重命名", systemImage: "pencil") {
                renameSessionText = s.title ?? ""
                renameSessionTarget = s
            }
            Button("分支", systemImage: "arrow.branch") {
                Task { await model.forkSession(sessionId: s.sessionId) }
            }
            Button("归档", systemImage: "archivebox", role: .destructive) {
                Task { await model.archiveSession(sessionId: s.sessionId) }
            }
        }
    }

    private var createProjectSheet: some View {
        NavigationStack {
            Form {
                Section("项目路径") {
                    TextField("/path/to/project", text: $newProjectPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("输入一个已存在的目录路径，将其纳为项目。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("新建项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { creatingProject = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        let p = newProjectPath.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !p.isEmpty { Task { _ = await model.createWorkspace(path: p) } }
                        creatingProject = false
                    }
                }
            }
        }
    }
}
