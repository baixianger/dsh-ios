import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""
    @State private var selectedWorkspaceId: String?
    @State private var selectedPresetId: String?
    @State private var selectedModel: DraftModelChoice?
    @State private var selectedPermission: String?
    @State private var showModelPicker = false
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 72)

            DSHHeroMark()

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    Menu {
                        ForEach(model.workspaces) { workspace in
                            Button(workspace.title) {
                                selectedWorkspaceId = workspace.workspaceId
                            }
                        }
                        Divider()
                        Button("添加工作区…", systemImage: "folder.badge.plus") {
                            model.requestNewChatDestination()
                        }
                    } label: {
                        Label {
                            Text(selectedWorkspace?.title ?? String(localized: "选择工作区"))
                        } icon: {
                            Image("DSHFolderClosed")
                                .renderingMode(.template)
                        }
                        .font(.subheadline.weight(.medium))
                    }

                    Menu {
                        ForEach(model.agentPresets) { preset in
                            Button(preset.displayName) {
                                selectedPresetId = preset.id
                            }
                        }
                    } label: {
                        Label {
                            Text(selectedPreset?.displayName ?? String(localized: "选择模式"))
                        } icon: {
                            Image("DSHAgentPreset")
                                .renderingMode(.template)
                        }
                        .font(.subheadline.weight(.medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                // DSH Web treats this as a control rail above the composer,
                // rather than aligning it mechanically to the input outline.
                .padding(.horizontal, 26)

                ComposerView(
                    draft: $draft,
                    isRunning: false,
                    modelLabel: selectedModelLabel,
                    permissionLabel: permissionName(selectedPermission ?? model.permissionPreset ?? "read-only"),
                    modelPickerEnabled: !model.modelCatalog.isEmpty,
                    submissionEnabled: selectedWorkspaceId != nil,
                    onOpenModelPicker: { showModelPicker = true },
                    onChangePermission: { selectedPermission = $0 },
                    onSend: sendFirstMessage,
                    onStop: {}
                )
                .disabled(isCreating)
            }
            .frame(maxWidth: 760)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            selectedWorkspaceId = selectedWorkspaceId ?? model.selectedWorkspaceId ?? model.workspaces.first?.workspaceId
            selectedPresetId = selectedPresetId
                ?? model.agentPresets.first(where: \.isDefault)?.id
                ?? model.agentPresets.first?.id
            selectedPermission = selectedPermission ?? model.permissionPreset
        }
        .sheet(isPresented: $showModelPicker) {
            DraftModelPickerSheet(groups: model.modelCatalog, selection: $selectedModel)
        }
    }

    private var selectedWorkspace: Workspace? {
        model.workspaces.first { $0.workspaceId == selectedWorkspaceId }
    }

    private var selectedPreset: AgentPreset? {
        model.agentPresets.first { $0.id == selectedPresetId }
    }

    private var selectedModelLabel: String {
        guard let selectedModel,
              let item = model.modelCatalog
                .first(where: { $0.id == selectedModel.providerId })?
                .models.first(where: { $0.id == selectedModel.modelId })
        else { return String(localized: "默认模型") }
        guard let reasoning = item.reasoning else { return item.name }
        let effort = selectedModel.effortId ?? reasoning.defaultEffort
        guard let effort,
              let effortName = reasoning.efforts.first(where: { $0.id == effort })?.name
        else { return item.name }
        return "\(item.name) · \(effortName)"
    }

    private func sendFirstMessage(image: UIImage?, text: String) {
        guard !isCreating, let workspaceId = selectedWorkspaceId else { return }
        isCreating = true
        Task {
            defer { isCreating = false }
            if let selectedPermission {
                await model.setPermission(selectedPermission)
            }
            guard let sessionId = await model.createSession(workspaceId: workspaceId, agentPreset: selectedPresetId) else {
                draft = text
                return
            }
            let session = model.sessionModel(for: sessionId)
            if let selectedModel {
                await session.selectModel(
                    provider: selectedModel.providerId,
                    model: selectedModel.modelId,
                    effort: selectedModel.effortId
                )
            }
            var imagePart: (data: String, mediaType: String)?
            if let image, let jpeg = image.jpegData(compressionQuality: 0.8) {
                imagePart = (jpeg.base64EncodedString(), "image/jpeg")
            }
            await session.send(text, image: imagePart)
        }
    }
}

struct DraftModelChoice: Equatable {
    let providerId: String
    let modelId: String
    let effortId: String?
}

private struct DraftModelPickerSheet: View {
    let groups: [ModelGroup]
    @Binding var selection: DraftModelChoice?
    @Environment(\.dismiss) private var dismiss
    @State private var providerId = ""
    @State private var modelId = ""
    @State private var effortId = ""

    private var selectedModel: ModelInfo? {
        groups.first(where: { $0.id == providerId })?
            .models.first(where: { $0.id == modelId })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("模型") {
                    ForEach(groups) { group in
                        ForEach(group.models) { item in
                            Button {
                                providerId = group.id
                                modelId = item.id
                                effortId = item.reasoning?.defaultEffort ?? ""
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).foregroundStyle(.primary)
                                        Text(group.name)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        if let description = item.description, !description.isEmpty {
                                            Text(description)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    if providerId == group.id && modelId == item.id {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }

                if let reasoning = selectedModel?.reasoning {
                    Section("思考强度") {
                        Picker("思考", selection: $effortId) {
                            if reasoning.defaultEffort == nil {
                                Text("提供商默认").tag("")
                            }
                            ForEach(reasoning.efforts) { effort in
                                Text(effort.name).tag(effort.id)
                            }
                        }
                        .pickerStyle(.navigationLink)

                        if let effort = reasoning.efforts.first(where: { $0.id == effortId }),
                           let description = effort.description, !description.isEmpty {
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        selection = DraftModelChoice(
                            providerId: providerId,
                            modelId: modelId,
                            effortId: effortId.isEmpty ? nil : effortId
                        )
                        dismiss()
                    }
                    .disabled(providerId.isEmpty || modelId.isEmpty)
                }
            }
            .onAppear {
                providerId = selection?.providerId ?? groups.first?.id ?? ""
                let group = groups.first(where: { $0.id == providerId }) ?? groups.first
                modelId = selection?.modelId ?? group?.models.first?.id ?? ""
                let item = group?.models.first(where: { $0.id == modelId })
                effortId = selection?.effortId ?? item?.reasoning?.defaultEffort ?? ""
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct NewChatDestinationView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let onDestinationSelected: () -> Void

    @State private var directoryPath = ""
    @State private var isCreatingWorkspace = false
    @State private var creationError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("选择工作区") {
                    if model.workspaces.isEmpty {
                        Text("还没有工作区")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.workspaces) { workspace in
                            Button {
                                select(workspaceId: workspace.workspaceId)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(workspace.title)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(workspace.path)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        directoryDestination
                    } label: {
                        Label("使用机器上的目录", systemImage: "folder.badge.plus")
                    }
                } footer: {
                    Text("目录指运行当前 DSH 服务的机器上的绝对路径。")
                }
            }
            .navigationTitle("新建聊天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var directoryDestination: some View {
        Form {
            Section {
                TextField("/Users/name/project", text: $directoryPath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("机器目录")
            } footer: {
                    Text("DSH 会把这个已存在的目录加入工作区列表。iOS 不会创建或浏览手机本地目录。")
            }
        }
        .navigationTitle("选择目录")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isCreatingWorkspace)
        .overlay {
            if isCreatingWorkspace {
                ProgressView("正在加入工作区…")
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("继续") { createWorkspaceAndContinue() }
                    .disabled(trimmedDirectoryPath.isEmpty || isCreatingWorkspace)
            }
        }
        .alert("无法使用该目录", isPresented: Binding(
            get: { creationError != nil },
            set: { if !$0 { creationError = nil } }
        )) {
            Button("好", role: .cancel) { creationError = nil }
        } message: {
            Text(creationError ?? "请确认目录存在，并且当前 DSH 主机可以访问。")
        }
    }

    private var trimmedDirectoryPath: String {
        directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func select(workspaceId: String) {
        model.newChat(workspaceId: workspaceId)
        onDestinationSelected()
        dismiss()
    }

    private func createWorkspaceAndContinue() {
        let path = trimmedDirectoryPath
        guard !path.isEmpty, !isCreatingWorkspace else { return }
        isCreatingWorkspace = true
        Task {
            if let workspaceId = await model.createWorkspace(path: path) {
                model.newChat(workspaceId: workspaceId)
                onDestinationSelected()
                dismiss()
            } else {
                creationError = "请确认目录存在，并且当前 DSH 主机可以访问这个绝对路径。"
            }
            isCreatingWorkspace = false
        }
    }
}

struct BlankChatView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""
    @State private var selectedModel: DraftModelChoice?
    @State private var selectedPermission: String?
    @State private var showModelPicker = false
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("开始新对话").font(.headline)
                Text("发送第一条消息后才会创建会话，并自动归属到当前工作区")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ComposerView(
                draft: $draft,
                isRunning: false,
                modelLabel: selectedModelLabel,
                permissionLabel: permissionName(selectedPermission ?? model.permissionPreset ?? "read-only"),
                modelPickerEnabled: !model.modelCatalog.isEmpty,
                submissionEnabled: model.selectedWorkspaceId != nil,
                onOpenModelPicker: { showModelPicker = true },
                onChangePermission: { selectedPermission = $0 },
                onSend: sendFirstMessage,
                onStop: {}
            )
            .disabled(isCreating)
            .overlay {
                if isCreating {
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                        .background(.regularMaterial, in: Circle())
                }
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear { selectedPermission = selectedPermission ?? model.permissionPreset }
        .sheet(isPresented: $showModelPicker) {
            DraftModelPickerSheet(groups: model.modelCatalog, selection: $selectedModel)
        }
    }

    private var selectedModelLabel: String {
        guard let selectedModel,
              let item = model.modelCatalog
                .first(where: { $0.id == selectedModel.providerId })?
                .models.first(where: { $0.id == selectedModel.modelId })
        else { return String(localized: "默认模型") }
        guard let reasoning = item.reasoning else { return item.name }
        let effort = selectedModel.effortId ?? reasoning.defaultEffort
        guard let effort,
              let effortName = reasoning.efforts.first(where: { $0.id == effort })?.name
        else { return item.name }
        return "\(item.name) · \(effortName)"
    }

    private func sendFirstMessage(image: UIImage?, text: String) {
        guard !isCreating else { return }
        isCreating = true
        let workspaceId = model.selectedWorkspaceId
        Task {
            defer { isCreating = false }
            if let selectedPermission {
                await model.setPermission(selectedPermission)
            }
            guard let sessionId = await model.createSession(workspaceId: workspaceId, agentPreset: nil) else {
                draft = text
                return
            }
            let session = model.sessionModel(for: sessionId)
            if let selectedModel {
                await session.selectModel(
                    provider: selectedModel.providerId,
                    model: selectedModel.modelId,
                    effort: selectedModel.effortId
                )
            }
            var imagePart: (data: String, mediaType: String)?
            if let image, let jpeg = image.jpegData(compressionQuality: 0.8) {
                imagePart = (jpeg.base64EncodedString(), "image/jpeg")
            }
            await session.send(text, image: imagePart)
            await model.loadSessions()
            await model.loadWorkspaces()
        }
    }
}
