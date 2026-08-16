import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL: String = ""
    @State private var editingCredential: CredentialView?
    @AppStorage("serverManualMode") private var isManualMode = false

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    Picker("连接方式", selection: $isManualMode) {
                        Text("自动扫描").tag(false)
                        Text("手动添加").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if isManualMode {
                        TextField("Base URL", text: $baseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button("保存并重连") {
                            model.baseURLString = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } else if model.isDiscovering {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在扫描 Tailscale 网络…").foregroundStyle(.secondary)
                        }
                    } else if model.discoveredHosts.isEmpty {
                        Button {
                            Task { await model.discoverHosts() }
                        } label: {
                            Label("扫描网络中的 DSH 主机", systemImage: "magnifyingglass")
                        }
                        Text("未发现主机。请确认运行 DSH 的主机已启动代理（端口 8080），且本机已登录同一 Tailscale 账号。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.discoveredHosts) { h in
                            Button {
                                model.baseURLString = h.baseURL.absoluteString
                                Task { await model.testConnection() }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(h.label).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                        if let m = h.model {
                                            Text(m).font(.caption).foregroundStyle(.secondary)
                                        }
                                        if let c = h.cwd {
                                            Text(c).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if model.baseURLString == h.baseURL.absoluteString {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                        Button("重新扫描") { Task { await model.discoverHosts() } }
                    }

                    Button("测试连接") {
                        Task { await model.testConnection() }
                    }
                    if let info = model.connectionInfo {
                        Text(info).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("模式（Agent Preset）") {
                    if model.agentPresets.isEmpty {
                        Text("无").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.agentPresets) { p in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(p.displayName)
                                        if p.isDefault { Text("默认").font(.caption2).foregroundStyle(.tint) }
                                    }
                                    Text(p.trust == "system" ? "系统" : "用户")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if p.trust == "user" {
                                    Button(role: .destructive) {
                                        Task { await model.removeAgentPreset(preset: p.id) }
                                    } label: { Label("删除", systemImage: "trash") }
                                }
                            }
                        }
                    }
                }

                Section("插件") {
                    if model.plugins.isEmpty {
                        Text("无").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.plugins) { p in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.moduleName).font(.subheadline.monospaced()).lineLimit(1)
                                    if let phase = p.fiberPhase, !phase.isEmpty {
                                        Text(phase).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: p.enabled ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(p.enabled ? .green : .secondary)
                            }
                        }
                    }
                }

                Section("模型提供商") {
                    if model.providers.isEmpty {
                        Text("无").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.providers) { p in
                            HStack {
                                Text(p.displayName)
                                Spacer()
                                if p.active {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }

                Section("凭证") {
                    if model.credentials.isEmpty {
                        Text("无").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.credentials) { c in
                            Button {
                                editingCredential = c
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.name).font(.subheadline.monospaced())
                                        Text(c.configured ? "已配置" : "未配置")
                                            .font(.caption)
                                            .foregroundStyle(c.configured ? .green : .secondary)
                                    }
                                    Spacer()
                                    Image(systemName: c.configured ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(c.configured ? .green : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("权限（沙箱模式）") {
                    let options = ["read-only", "workspace-write", "danger-full-access"]
                    ForEach(options, id: \.self) { opt in
                        Button {
                            Task { await model.setPermission(opt) }
                        } label: {
                            HStack {
                                Text(permissionLabel(opt))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if model.permissionPreset == opt {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                    Text("控制会话的沙箱权限（读写文件的范围）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("模型目录") {
                    if model.modelCatalog.isEmpty {
                        Text("无").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.modelCatalog) { group in
                            DisclosureGroup(group.name) {
                                ForEach(group.models) { m in
                                    Text(m.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if model.isOffline {
                    Section("离线提示") {
                        Text("当前无法连接。请确认运行 DSH 的主机和本 iPhone 都已安装并登录 Tailscale（同一账号），并用 tailscale serve 暴露 DSH 后，把上面的 Base URL 改成 tailnet HTTPS 地址。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("说明") {
                    Text("本 App 是 DeepSeek Harness 的原生客户端，通过 HTTP RPC + WebSocket 事件流与服务器通信。远程访问时服务器需信任你的 tailnet 域名（--trusted-host）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(Color.secondary.opacity(0.12), in: Circle())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
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
            .sheet(item: $editingCredential) { c in
                CredentialEditorSheet(credential: c)
            }
        }
    }

    private func permissionLabel(_ opt: String) -> String {
        switch opt {
        case "read-only": return "只读"
        case "workspace-write": return "工作区可写"
        case "danger-full-access": return "完全访问"
        default: return opt
        }
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
                    SecureField(credential.configured ? "输入新值以更新（留空不改）" : "输入 API Key", text: $value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if credential.configured {
                    Section {
                        Button("清除凭证", role: .destructive) {
                            Task { await model.unsetCredential(ref: credential.name) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("凭证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !v.isEmpty {
                            Task { await model.setCredential(ref: credential.name, value: v) }
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
