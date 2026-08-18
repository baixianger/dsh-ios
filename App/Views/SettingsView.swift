import SwiftUI

private enum SettingsDestination: String, CaseIterable, Identifiable, Hashable {
    case connection, general, models, agentPresets, plugins
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .connection: "连接与配对"
        case .general: "通用设置"
        case .models: "模型设置"
        case .agentPresets: "Agent 预设"
        case .plugins: "插件"
        }
    }

    var systemImage: String {
        switch self {
        case .connection: "link"
        case .general: "gearshape"
        case .models: "externaldrive"
        case .agentPresets: "circle.hexagongrid"
        case .plugins: "puzzlepiece.extension"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("serverManualMode") private var isManualMode = false
    @AppStorage("dsh.appearance") private var appearance = "system"
    @State private var selection: SettingsDestination? = .general
    @State private var baseURL = ""
    @State private var editingCredential: CredentialView?
    @State private var editingServer: DshServer?
    @State private var isAddingServer = false
    @State private var pluginSearch = ""

    var body: some View {
        Group {
            if usesPhoneNavigation {
                compactSettings
            } else {
                regularSettings
            }
        }
        .onAppear {
            baseURL = model.baseURLString
            if !isManualMode && model.discoveredHosts.isEmpty {
                Task { await model.discoverHosts() }
            }
        }
        .onChange(of: isManualMode) { _, manual in
            if !manual && model.discoveredHosts.isEmpty {
                Task { await model.discoverHosts() }
            }
        }
        .sheet(item: $editingCredential) { credential in
            CredentialEditorSheet(credential: credential)
        }
        .sheet(item: $editingServer) { server in
            ServerEditorSheet(server: server)
        }
        .sheet(isPresented: $isAddingServer) {
            ServerEditorSheet(server: nil)
        }
        .alert("设置操作失败", isPresented: Binding(
            get: { model.settingsError != nil },
            set: { if !$0 { model.settingsError = nil } }
        )) {
            Button("好", role: .cancel) { model.settingsError = nil }
        } message: {
            Text(model.settingsError ?? "未知错误")
        }
    }

    private var usesPhoneNavigation: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var compactSettings: some View {
        NavigationStack {
            List(SettingsDestination.allCases) { destination in
                NavigationLink(value: destination) {
                    Label(destination.title, systemImage: destination.systemImage)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsDestination.self) { destination in
                detail(for: destination)
            }
            .toolbar { closeToolbar }
        }
    }

    private var regularSettings: some View {
        NavigationStack {
            HStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(SettingsDestination.allCases) { destination in
                        Label(destination.title, systemImage: destination.systemImage)
                            .tag(destination)
                    }
                }
                .frame(width: 250)

                Divider()

                detail(for: selection ?? .general)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { closeToolbar }
        }
    }

    @ToolbarContentBuilder
    private var closeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("关闭", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
        }
    }

    @ViewBuilder
    private func detail(for destination: SettingsDestination) -> some View {
        switch destination {
        case .connection: connectionPage
        case .general: generalPage
        case .models: modelsPage
        case .agentPresets: agentPresetsPage
        case .plugins: pluginsPage
        }
    }

    private var connectionPage: some View {
        settingsPage(title: "连接与配对", intro: "连接运行 DeepSeek Harness 的主机。自动发现与手动地址是 iOS 客户端特有能力。") {
            settingsCard {
                HStack {
                    Text("DSH Servers").font(.headline)
                    Spacer()
                    Button("添加", systemImage: "plus") {
                        isAddingServer = true
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("添加 DSH Server")
                }

                if model.servers.isEmpty {
                    Text("尚未连接 DSH Server")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.servers) { server in
                            HStack(spacing: 12) {
                                Button {
                                    model.activateServer(server.id)
                                    baseURL = server.baseURLString
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "desktopcomputer")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 24)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(server.name)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                            Text(server.baseURLString)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if model.activeServerID == server.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Menu {
                                    Button("编辑", systemImage: "pencil") {
                                        editingServer = server
                                    }
                                    Button("删除", systemImage: "trash", role: .destructive) {
                                        model.removeServer(server)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, height: 32)
                                }
                                .accessibilityLabel("管理 \(server.name)")
                            }
                            .padding(.vertical, 8)
                            if server.id != model.servers.last?.id { Divider() }
                        }
                    }
                }

                Divider()

                Picker("连接方式", selection: $isManualMode) {
                    Text("自动发现").tag(false)
                    Text("手动地址").tag(true)
                }
                .pickerStyle(.segmented)

                if isManualMode {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Base URL").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        TextField("https://host.example", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    Button("保存并重连") {
                        let value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        model.addServer(name: URL(string: value)?.host ?? "DSH Server", baseURLString: value)
                    }
                    .buttonStyle(.borderedProminent)
                } else if model.isDiscovering {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text("正在发现 DSH 主机…").foregroundStyle(.secondary)
                    }
                } else if model.discoveredHosts.isEmpty {
                    Text("没有发现可配对的主机。请确认设备位于同一 Tailscale 网络。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("重新扫描", systemImage: "arrow.clockwise") {
                        Task { await model.discoverHosts() }
                    }
                    .buttonStyle(.bordered)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.discoveredHosts) { host in
                            Button {
                                model.connectDiscoveredHost(host)
                                baseURL = host.baseURL.absoluteString
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "desktopcomputer").foregroundStyle(.secondary).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(host.label).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                        Text(host.baseURL.absoluteString)
                                            .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                        if let cwd = host.cwd, !cwd.isEmpty {
                                            Text(cwd).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if model.activeServer?.hostID == host.hostID || model.baseURLString == host.baseURL.absoluteString {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    }
                                }
                                .padding(.vertical, 8).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if host.id != model.discoveredHosts.last?.id { Divider() }
                        }
                    }
                }

                Divider()
                HStack {
                    Button("测试连接", systemImage: "bolt.horizontal.circle") {
                        Task { await model.testConnection() }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    if let info = model.connectionInfo {
                        Text(info).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }
    }

    private var generalPage: some View {
        settingsPage(title: "通用设置", intro: nil) {
            VStack(alignment: .leading, spacing: 10) {
                Text("外观").font(.headline)
                HStack(spacing: 10) {
                    appearanceChoice("light", title: "浅色", systemImage: "sun.max")
                    appearanceChoice("dark", title: "深色", systemImage: "moon")
                    appearanceChoice("system", title: "跟随系统", systemImage: "circle.lefthalf.filled")
                }
            }

            settingsCard {
                HStack(alignment: .top, spacing: 12) {
                    Image("DSHAgentPreset").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 20, height: 20).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agent 预设").font(.subheadline.weight(.semibold))
                        Text("对此后新建的会话生效。运行中的会话保持它开始时的预设。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    if model.agentPresets.isEmpty {
                        Text("不可用").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Menu {
                            ForEach(model.agentPresets) { preset in
                                Button {
                                    Task { await model.setDefaultAgentPreset(preset.id) }
                                } label: {
                                    if preset.isDefault { Label(preset.displayName, systemImage: "checkmark") }
                                    else { Text(preset.displayName) }
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(model.agentPresets.first(where: \.isDefault)?.displayName ?? model.agentPresets[0].displayName)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down").font(.caption2)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    private var modelsPage: some View {
        settingsPage(title: "模型设置", intro: "填入各提供方的 API 密钥即可使用其模型。") {
            if model.providers.isEmpty { emptyState("没有可用的模型提供方") }
            else { ForEach(model.providers) { providerCard($0) } }

            VStack(alignment: .leading, spacing: 10) {
                Text("API 密钥").font(.headline)
                if model.credentials.isEmpty {
                    emptyState("此部署没有可编辑的 API 密钥")
                } else {
                    ForEach(model.credentials) { credential in
                        Button {
                            guard credential.writable else { return }
                            editingCredential = credential
                        } label: {
                            settingsCard {
                                HStack(spacing: 10) {
                                    Circle().fill(credential.configured ? Color.green : Color.red).frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(credential.name).font(.subheadline.monospaced().weight(.medium)).foregroundStyle(.primary)
                                        Text(credential.configured ? "API 密钥已配置" : "API 密钥缺失")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if credential.writable {
                                        Text("编辑").font(.caption.weight(.medium))
                                        Image(systemName: "chevron.right").font(.caption2)
                                    } else {
                                        Label("只读", systemImage: "lock.fill")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!credential.writable)
                        .accessibilityHint(credential.writable ? "编辑 API 密钥" : "此凭证由主机管理，不能从远端修改")
                    }
                }
            }
        }
    }

    private var agentPresetsPage: some View {
        settingsPage(title: "Agent 预设", intro: "预设是一个会话所运行的插件组合，包括工具、提示词与能力。") {
            presetGroup(title: "内置", presets: model.agentPresets.filter { $0.trust == "system" })
            presetGroup(title: "自定义", presets: model.agentPresets.filter { $0.trust != "system" })
        }
    }

    private var pluginsPage: some View {
        settingsPage(title: "插件", intro: "配置和查看本部署已安装的插件。") {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索插件", text: $pluginSearch).textFieldStyle(.plain)
                if !pluginSearch.isEmpty {
                    Button("清除搜索", systemImage: "xmark.circle.fill") { pluginSearch = "" }
                        .labelStyle(.iconOnly).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(Color.dsSurfacePrimary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))

            if filteredPlugins.isEmpty {
                emptyState(pluginSearch.isEmpty ? "暂无插件" : "没有匹配的插件")
            } else {
                ForEach(filteredPlugins) { plugin in
                    settingsCard {
                        HStack(spacing: 10) {
                            Circle().fill(pluginStatusColor(plugin)).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(plugin.moduleName).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(pluginStatusLabel(plugin)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(plugin.enabled ? "已启用" : "已停用")
                                .font(.caption2.weight(.medium)).foregroundStyle(plugin.enabled ? .green : .secondary)
                                .padding(.horizontal, 7).frame(height: 22)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
            }
        }
    }

    private func appearanceChoice(_ value: String, title: LocalizedStringKey, systemImage: String) -> some View {
        Button { appearance = value } label: {
            VStack(spacing: 7) {
                Image(systemName: systemImage).font(.title3)
                Text(title).font(.caption.weight(.medium))
            }
            .foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 68)
            .background(appearance == value ? Color.dsSurfaceSelected : Color.dsSurfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(appearance == value ? Color.primary : Color.secondary.opacity(0.18), lineWidth: appearance == value ? 1.2 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(appearance == value ? .isSelected : [])
    }

    private func providerCard(_ provider: ProviderView) -> some View {
        settingsCard {
            HStack(spacing: 9) {
                Circle().fill(provider.active ? Color.green : Color.secondary.opacity(0.45)).frame(width: 8, height: 8)
                Text(provider.displayName).font(.subheadline.weight(.semibold))
                if provider.provider != provider.displayName {
                    Text(provider.provider).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).frame(height: 20)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
                }
                Spacer()
                Text(provider.active ? "可用" : "未启用").font(.caption).foregroundStyle(.secondary)
            }
            if let catalog = model.modelCatalog.first(where: { $0.id == provider.provider }) {
                DisclosureGroup("模型目录（\(catalog.models.count)）") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(catalog.models) { entry in
                            HStack {
                                Text(entry.name).font(.caption)
                                Spacer()
                                Text(entry.id).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.caption.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private func presetGroup(title: LocalizedStringKey, presets: [AgentPreset]) -> some View {
        if !presets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .textCase(.uppercase).tracking(0.6)
                ForEach(presets) { preset in
                    settingsCard {
                        HStack(alignment: .top, spacing: 10) {
                            Image("DSHAgentPreset").renderingMode(.template).resizable().scaledToFit()
                                .frame(width: 18, height: 18).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 7) {
                                    Text(preset.displayName).font(.subheadline.weight(.semibold))
                                    if preset.isDefault {
                                        Text("当前使用").font(.caption2.weight(.medium))
                                            .foregroundStyle(Color(uiColor: .systemBackground))
                                            .padding(.horizontal, 7).frame(height: 20)
                                            .background(Color.primary, in: Capsule())
                                    }
                                }
                                Text(preset.description ?? "暂无说明")
                                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                Text(preset.id).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 8)
                            if !preset.isDefault {
                                Menu {
                                    Button("设为默认", systemImage: "checkmark.circle") {
                                        Task { await model.setDefaultAgentPreset(preset.id) }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis").frame(width: 36, height: 36).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var filteredPlugins: [PluginEntry] {
        let query = pluginSearch.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !query.isEmpty else { return model.plugins }
        return model.plugins.filter {
            $0.moduleName.localizedLowercase.contains(query)
                || ($0.fiberPhase ?? "").localizedLowercase.contains(query)
        }
    }

    private func pluginStatusLabel(_ plugin: PluginEntry) -> LocalizedStringKey {
        switch plugin.fiberPhase {
        case "active": "已挂载"
        case "failed": "挂载失败"
        case "loading": "加载中"
        case "pending": "等待依赖"
        case "unloading": "卸载中"
        default: "未挂载"
        }
    }

    private func pluginStatusColor(_ plugin: PluginEntry) -> Color {
        switch plugin.fiberPhase {
        case "active": .green
        case "failed": .red
        case "loading": .blue
        default: .secondary
        }
    }

    private func settingsPage<Content: View>(title: LocalizedStringKey, intro: LocalizedStringKey?, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.title2.weight(.semibold))
                    if let intro { Text(intro).font(.subheadline).foregroundStyle(.secondary) }
                }
                content()
            }
            .frame(maxWidth: 760, alignment: .leading).padding(20)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsSurfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.secondary.opacity(0.16), lineWidth: 0.5) }
    }

    private func emptyState(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(Color.dsSurfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct CredentialEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    let credential: CredentialView
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(credential.name) {
                    if credential.writable {
                        SecureField(credential.configured ? "输入新值以更新（留空不改）" : "输入 API 密钥", text: $value)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    } else {
                        Label("此凭证由主机管理，不能从远端修改", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                if credential.configured && credential.writable {
                    Section {
                        Button("清除凭证", role: .destructive) {
                            Task {
                                await model.unsetCredential(ref: credential.name)
                                if model.settingsError == nil { dismiss() }
                            }
                        }
                    }
                }
            }
            .navigationTitle("API 密钥")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        Task {
                            await model.setCredential(ref: credential.name, value: trimmed)
                            if model.settingsError == nil { dismiss() }
                        }
                    }
                    .disabled(!credential.writable || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert("设置操作失败", isPresented: Binding(
            get: { model.settingsError != nil },
            set: { if !$0 { model.settingsError = nil } }
        )) {
            Button("好", role: .cancel) { model.settingsError = nil }
        } message: {
            Text(model.settingsError ?? "未知错误")
        }
    }
}

private struct ServerEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let server: DshServer?

    @State private var name: String
    @State private var baseURLString: String

    init(server: DshServer?) {
        self.server = server
        _name = State(initialValue: server?.name ?? "")
        _baseURLString = State(initialValue: server?.baseURLString ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("DSH Server") {
                    TextField("名称", text: $name)
                    TextField("https://host.example", text: $baseURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            .navigationTitle(server == nil ? "添加 Server" : "编辑 Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        if let server {
            model.updateServer(server, name: name, baseURLString: baseURLString)
        } else {
            model.addServer(name: name, baseURLString: baseURLString)
        }
        dismiss()
    }
}
