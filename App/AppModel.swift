import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    var baseURLString: String {
        didSet {
            UserDefaults.standard.set(baseURLString, forKey: "dshBaseURL")
            client = DshClient(baseURL: URL(string: baseURLString) ?? URL(string: "http://127.0.0.1:3080")!)
            Task {
                await loadSessions()
                startEvents()
            }
        }
    }

    private(set) var client: DshClient
    @Published var sessions: [SessionSummary] = []
    @Published var sessionsError: String?
    @Published var isLoadingSessions = false
    @Published var connectionInfo: String?
    @Published var isOffline = false
    @Published var showSettings = false
    @Published var showSidebar = false

    @Published var pendingApprovals: [ApprovalWait] = []
    @Published var pendingQuestions: [QuestionWait] = []

    @Published var workspaces: [Workspace] = []
    @Published var selectedWorkspaceId: String?
    @Published var selectedConversationId: String?
    @Published var lastConversationByProject: [String: String] = [:]
    @Published var searchQuery = ""
    @Published var agentPresets: [AgentPreset] = []
    @Published var providers: [ProviderView] = []
    @Published var credentials: [CredentialView] = []
    @Published var modelCatalog: [ModelGroup] = []
    @Published var plugins: [PluginEntry] = []
    @Published var discoveredHosts: [DiscoveredHost] = []
    @Published var isDiscovering = false
    @Published var permissionPreset: String?
    @Published var permissionRevision: Double = 0

    private var openSessions: [String: SessionModel] = [:]
    private var eventTask: Task<Void, Never>?

    init() {
        let stored = UserDefaults.standard.string(forKey: "dshBaseURL") ?? "http://127.0.0.1:3080"
        self.baseURLString = stored
        self.client = DshClient(baseURL: URL(string: stored) ?? URL(string: "http://127.0.0.1:3080")!)
    }

    func boot() async {
        await loadSessions()
        await loadWorkspaces()
        await loadAgentPresets()
        await loadProviders()
        await loadCredentials()
        await loadModelCatalog()
        await loadPermission()
        await loadPlugins()
        startEvents()
    }

    func loadPlugins() async {
        do {
            let value = try await client.callRemote("pluginInventory", "list", args: .object([:]))
            plugins = (value["entries"]?.array ?? []).compactMap { PluginEntry(json: $0) }
        } catch {}
    }

    func loadAgentPresets() async {
        do {
            let value = try await client.call("agentPreset.list")
            agentPresets = (value["presets"]?.array ?? []).compactMap { AgentPreset(json: $0) }
        } catch {}
    }

    func removeAgentPreset(preset: String) async {
        do {
            let _ = try await client.call("agentPreset.remove", payload: .object(["agentPreset": .string(preset)]))
            await loadAgentPresets()
        } catch {}
    }

    func selectAgentPreset(sessionId: String, preset: String) async {
        do {
            let _ = try await client.call("agentPreset.select", payload: .object(["sessionId": .string(sessionId), "agentPreset": .string(preset)]))
        } catch {}
    }

    func loadProviders() async {
        do {
            let value = try await client.call("llm.providers")
            providers = (value["providers"]?.array ?? []).compactMap { ProviderView(json: $0) }
        } catch {}
    }

    func loadCredentials() async {
        let refs = ["DEEPSEEK_API_KEY", "PI_API_KEY"]
        do {
            let value = try await client.call("credentials.describe", payload: .object(["refs": .array(refs.map { .string($0) })]))
            let dict = value["credentials"]?.object ?? [:]
            credentials = refs.compactMap { name in
                guard let v = dict[name] else { return nil }
                return CredentialView(name: name, configured: v["configured"]?.bool ?? false, writable: v["writable"]?.bool ?? false)
            }
        } catch {}
    }

    func setCredential(ref: String, value: String) async {
        do {
            let _ = try await client.call("credentials.set", payload: .object(["ref": .string(ref), "value": .string(value)]))
            await loadCredentials()
        } catch {}
    }

    func unsetCredential(ref: String) async {
        do {
            let _ = try await client.call("credentials.unset", payload: .object(["ref": .string(ref)]))
            await loadCredentials()
        } catch {}
    }

    func loadModelCatalog() async {
        do {
            let value = try await client.call("llm.models")
            modelCatalog = (value["groups"]?.array ?? []).compactMap { ModelGroup(json: $0) }
        } catch {}
    }

    func loadSessions() async {
        isLoadingSessions = true
        defer { isLoadingSessions = false }
        do {
            let value = try await client.call("session.list")
            let items = value["items"]?.array ?? []
            sessions = items.compactMap { SessionSummary(json: $0) }
            sessionsError = nil
            isOffline = false
        } catch {
            sessionsError = String(describing: error)
            isOffline = true
        }
    }

    func loadWorkspaces() async {
        do {
            let value = try await client.call("workspace.list")
            workspaces = (value["items"]?.array ?? []).compactMap { Workspace(json: $0) }
            if selectedWorkspaceId == nil || !workspaces.contains(where: { $0.workspaceId == selectedWorkspaceId }) {
                selectedWorkspaceId = workspaces.first?.workspaceId
            }
        } catch {}
    }

    func createSession(workspaceId: String?, agentPreset: String?) async -> String? {
        var payload: [String: JSONValue] = [:]
        if let workspaceId { payload["workspaceId"] = .string(workspaceId) }
        if let agentPreset { payload["agentPreset"] = .string(agentPreset) }
        do {
            let value = try await client.call("session.create", payload: .object(payload))
            let id = value["sessionId"]?.string
            await loadSessions()
            if let id {
                selectedConversationId = id
                if let workspaceId {
                    selectedWorkspaceId = workspaceId
                    lastConversationByProject[workspaceId] = id
                }
            }
            return id
        } catch {
            return nil
        }
    }

    func conversations(in projectId: String) -> [SessionSummary] {
        guard let ws = workspaces.first(where: { $0.workspaceId == projectId }) else { return [] }
        return sessions
            .filter { ws.sessionIds.contains($0.sessionId) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func selectProject(_ id: String?) {
        selectedWorkspaceId = id
        selectedConversationId = id.flatMap { lastConversationByProject[$0] }
    }

    func selectConversation(_ id: String) {
        selectedConversationId = id
        if let ws = workspaces.first(where: { $0.sessionIds.contains(id) }) {
            selectedWorkspaceId = ws.workspaceId
            lastConversationByProject[ws.workspaceId] = id
        }
    }

    func newChat() async {
        let pid = selectedWorkspaceId ?? workspaces.first?.workspaceId
        _ = await createSession(workspaceId: pid, agentPreset: nil)
    }

    func renameSession(sessionId: String, title: String) async {
        do {
            let _ = try await client.call("session.rename", payload: .object(["sessionId": .string(sessionId), "title": .string(title)]))
            await loadSessions()
        } catch {}
    }

    func archiveSession(sessionId: String) async {
        do {
            let _ = try await client.call("workspace.archiveSession", payload: .object(["sessionId": .string(sessionId)]))
            await loadSessions()
        } catch {}
    }

    func forkSession(sessionId: String) async {
        do {
            let _ = try await client.call("session.fork", payload: .object(["sessionId": .string(sessionId)]))
            await loadSessions()
        } catch {}
    }

    func createWorkspace(path: String) async -> String? {
        do {
            let value = try await client.call("workspace.create", payload: .object(["path": .string(path)]))
            let wid = value["workspace"]?["workspaceId"]?.string
            await loadWorkspaces()
            if let wid {
                selectedWorkspaceId = wid
                selectedConversationId = nil
            }
            return wid
        } catch {
            return nil
        }
    }

    func renameWorkspace(workspaceId: String, title: String) async {
        do {
            let _ = try await client.call("workspace.rename", payload: .object(["workspaceId": .string(workspaceId), "title": .string(title)]))
            await loadWorkspaces()
        } catch {}
    }

    func deleteWorkspace(workspaceId: String) async {
        do {
            let _ = try await client.call("workspace.delete", payload: .object(["workspaceId": .string(workspaceId)]))
            if selectedWorkspaceId == workspaceId {
                selectedWorkspaceId = nil
                selectedConversationId = nil
            }
            await loadWorkspaces()
        } catch {}
    }

    var visibleSessions: [SessionSummary] {
        var result = sessions
        if let wid = selectedWorkspaceId, let ws = workspaces.first(where: { $0.workspaceId == wid }) {
            result = result.filter { ws.sessionIds.contains($0.sessionId) }
        }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            result = result.filter { ($0.title ?? "").localizedCaseInsensitiveContains(q) || ($0.cwd ?? "").localizedCaseInsensitiveContains(q) }
        }
        return result
    }

    func loadPermission() async {
        do {
            let value = try await client.call("settings.describe")
            if let perm = (value["namespaces"]?.array ?? []).first(where: { $0["ns"]?.string == "permission" }) {
                permissionPreset = perm["value"]?["defaultPreset"]?.string
                permissionRevision = perm["revision"]?.double ?? 0
            }
        } catch {}
    }

    func setPermission(_ preset: String) async {
        do {
            let _ = try await client.call("settings.update", payload: .object([
                "ns": .string("permission"),
                "patch": .object(["defaultPreset": .string(preset)]),
                "expectedRevision": .number(permissionRevision),
            ]))
            await loadPermission()
        } catch {}
    }

    func discoverHosts() async {
        isDiscovering = true
        defer { isDiscovering = false }
        discoveredHosts = await HostDiscovery.discover()
    }

    func testConnection() async {
        do {
            let host: HostInfo = try await client.call("host.describe", as: HostInfo.self)
            connectionInfo = "已连接 \(host.model ?? "?") @ \(host.cwd)"
            isOffline = false
        } catch {
            connectionInfo = "连接失败: \(error)"
            isOffline = true
        }
    }

    func sessionModel(for sessionId: String) -> SessionModel {
        if let existing = openSessions[sessionId] { return existing }
        let model = SessionModel(sessionId: sessionId, client: client)
        model.summary = sessions.first { $0.sessionId == sessionId }
        openSessions[sessionId] = model
        return model
    }

    func startEvents() {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.pumpMux() }
                group.addTask { await self.pumpHost() }
            }
        }
    }

    private func pumpMux() async {
        do {
            for try await frame in client.muxEvents() {
                handleMux(frame)
            }
        } catch {}
    }

    private func pumpHost() async {
        do {
            for try await frame in client.hostEvents() {
                handleHost(frame)
            }
        } catch {}
    }

    private func handleMux(_ frame: ServerRequest) {
        switch frame.method {
        case "session/event":
            if let sessionId = frame.payload["sessionId"]?.string,
               let model = openSessions[sessionId] {
                model.apply(event: frame.payload["event"] ?? .null, view: frame.payload["view"])
            }
        case "approval/requested":
            if let wait = ApprovalWait(rpcId: frame.rpcId, payload: frame.payload) {
                pendingApprovals.append(wait)
            }
        case "approval/resolved":
            if let id = frame.payload["approvalId"]?.string {
                pendingApprovals.removeAll { $0.approvalId == id }
            }
        case "question/requested":
            if let wait = QuestionWait(rpcId: frame.rpcId, payload: frame.payload) {
                pendingQuestions.append(wait)
            }
        case "question/resolved":
            pendingQuestions.removeAll { $0.rpcId == frame.rpcId }
        case "session/jobs":
            if let sessionId = frame.payload["sessionId"]?.string,
               let model = openSessions[sessionId] {
                model.setJobs(frame.payload["jobs"] ?? .null)
            }
        case "session/projection":
            if let sessionId = frame.payload["sessionId"]?.string,
               let key = frame.payload["key"]?.string,
               let model = openSessions[sessionId] {
                model.updateProjection(key: key, value: frame.payload["value"] ?? .null)
            }
        default:
            break
        }
    }

    private func handleHost(_ frame: ServerRequest) {
        switch frame.method {
        case "host/session-status":
            if let sessionId = frame.payload["sessionId"]?.string,
               let running = frame.payload["running"]?.bool,
               let idx = sessions.firstIndex(where: { $0.sessionId == sessionId }) {
                sessions[idx].running = running
            }
        case "host/session-added", "host/session-removed", "host/workspace-changed",
             "host/workspace-removed", "host/workspace-order-changed", "host/archived-sessions-changed":
            Task { await loadSessions() }
        default:
            break
        }
    }
}
