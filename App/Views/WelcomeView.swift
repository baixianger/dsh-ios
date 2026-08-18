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

enum ServerOnboardingStep: Int, CaseIterable, Equatable {
    case server
    case network
    case pair

    var title: LocalizedStringKey {
        switch self {
        case .server: "先配置 DSH 主机"
        case .network: "选择连接方式"
        case .pair: "扫描二维码，安全配对"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .server: "在运行 DSH 的机器上打开终端，安装网络插件。"
        case .network: "运行配置命令生成二维码，然后选择 LAN、Tailscale 或自定义地址。"
        case .pair: "在五分钟内扫描一次性二维码。配对后，当前设备会安全保存这台 DSH 主机。"
        }
    }

    var symbol: String {
        switch self {
        case .server: "terminal"
        case .network: "network"
        case .pair: "qrcode.viewfinder"
        }
    }
}

struct ServerOnboardingFlowState: Equatable {
    var step: ServerOnboardingStep = .server

    var isLastStep: Bool { step == .pair }

    mutating func advance() {
        guard let next = ServerOnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }
}

struct ServerOnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var flow = ServerOnboardingFlowState()
    @State private var isPairing = false
    @State private var isShowingConnections = false
    @State private var scanLineAtBottom = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                DSHBrandTitle()
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            TabView(selection: $flow.step) {
                ForEach(ServerOnboardingStep.allCases, id: \.rawValue) { step in
                    onboardingPage(step)
                        .tag(step)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(ServerOnboardingStep.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step == flow.step ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(width: step == flow.step ? 24 : 8, height: 8)
                        .animation(.easeInOut(duration: 0.22), value: flow.step)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("第 \(flow.step.rawValue + 1) 页，共 3 页")
                .padding(.bottom, 8)

                Button(flow.isLastStep ? "开始配对" : "下一步") {
                    if flow.isLastStep {
                        isPairing = true
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) { flow.advance() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: 560)
                .accessibilityIdentifier("server-onboarding-primary-action")
                .padding(.horizontal, 24)

                Button("手动添加 DSH 主机") {
                    isShowingConnections = true
                }
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 38)
                .accessibilityIdentifier("server-onboarding-manual-action")
            }
            .padding(.top, 10)
            .padding(.bottom, 4)
            .background(Color(uiColor: .systemBackground))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $isPairing) {
            DshNetworkPairingSheet()
        }
        .sheet(isPresented: $isShowingConnections) {
            SettingsView(openingConnection: true)
        }
    }

    private func onboardingPage(_ step: ServerOnboardingStep) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: step.symbol)
                    .font(.system(.title, design: .rounded, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 72, height: 72)
                    .background(Color.accentColor.opacity(0.10), in: Circle())
                    .accessibilityHidden(true)

                Text(step.title)
                    .font(.title.bold())
                    .tracking(-0.35)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.leading)

                Text(step.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if step == .server {
                    installCommand
                } else if step == .network {
                    setupCommand
                } else {
                    pairingPreview
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("server-onboarding-page-\(step.rawValue + 1)")
    }

    private var installCommand: some View {
        terminalCard(command: "dsh plugin --profile web add dsh-network@next")
            .padding(.top, 2)
    }

    private var setupCommand: some View {
        terminalCard(
            command: "dsh plugin --profile web exec dsh-network setup",
            output: [
                "Choose a connection method / 选择连接方式:",
                "  1. LAN / 家庭或局域网",
                "  2. Tailscale / Tailnet",
                "  3. Custom address / 自定义地址",
            ]
        )
        .padding(.top, 2)
    }

    private func terminalCard(command: String, output: [String] = []) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(terminalForeground.opacity(0.22)).frame(width: 9, height: 9)
                Circle().fill(terminalForeground.opacity(0.38)).frame(width: 9, height: 9)
                Circle().fill(terminalForeground.opacity(0.54)).frame(width: 9, height: 9)

                Spacer()

                Text("DSH Host")
                    .font(.caption2.monospaced())
                    .foregroundStyle(terminalForeground.opacity(0.58))

                Button {
                    UIPasteboard.general.string = command
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(terminalForeground.opacity(0.72))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制命令")
            }
            .padding(.leading, 14)
            .padding(.trailing, 7)
            .frame(height: 38)

            Divider()
                .overlay(terminalForeground.opacity(0.10))

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Text("$")
                        .foregroundStyle(terminalForeground.opacity(0.58))

                    Text(command)
                        .foregroundStyle(terminalForeground)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }

                if !output.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(output, id: \.self) { line in
                            Text(line)
                                .foregroundStyle(terminalForeground.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .font(.caption.monospaced())
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        }
        .background(
            terminalBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(terminalForeground.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: colorScheme == .light ? .black.opacity(0.06) : .clear, radius: 8, y: 3)
    }

    private var terminalBackground: Color {
        Color(uiColor: .secondarySystemBackground)
    }

    private var terminalForeground: Color {
        Color(uiColor: .label)
    }

    private var pairingPreview: some View {
        HStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(terminalForeground.opacity(0.18), lineWidth: 1)
                    }

                Capsule()
                    .fill(terminalForeground.opacity(0.22))
                    .frame(width: 28, height: 4)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 9)

                ZStack {
                    Image(systemName: "qrcode")
                        .font(.system(size: 62, weight: .regular))
                        .foregroundStyle(terminalForeground)

                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 72, height: 2)
                        .shadow(color: Color.accentColor.opacity(0.5), radius: 4)
                        .offset(y: scanLineAtBottom ? 32 : -32)
                        .animation(
                            .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                            value: scanLineAtBottom
                        )
                }
            }
            .frame(width: 104, height: 142)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Label("一次性配对", systemImage: "lock.shield")
                    .font(.headline)

                Text("5 分钟内有效")
                    .font(.title3.monospacedDigit().weight(.semibold))

                Text("请扫描运行 DSH 的主机终端中生成的二维码")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            terminalBackground,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(terminalForeground.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: colorScheme == .light ? .black.opacity(0.05) : .clear, radius: 8, y: 3)
        .padding(.top, 2)
        .onAppear { scanLineAtBottom = true }
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
