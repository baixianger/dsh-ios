import Foundation
import Combine

struct ServerWorkspaceSnapshot: Identifiable {
    let server: DshServer
    let workspaces: [Workspace]
    let sessions: [SessionSummary]
    let archivedSessionIds: Set<String>

    var id: UUID { server.id }
}

private struct SidebarDestination {
    let serverID: UUID
    let workspaceID: String?
    let sessionID: String?
}

@MainActor
final class AppModel: ObservableObject {
    enum MainPresentation: Equatable {
        case blank
        case welcome
        case workspace
        case conversation
    }
    var baseURLString: String {
        didSet {
            guard baseURLString != oldValue else { return }
            UserDefaults.standard.set(baseURLString, forKey: "dshBaseURL")
            if let activeServerID,
               let index = servers.firstIndex(where: { $0.id == activeServerID }) {
                servers[index].baseURLString = baseURLString
                persistServers()
            }
            client = Self.makeClient(baseURLString: baseURLString, credentialKey: activeServer?.credentialKey)

            // Every one of these collections is scoped to a DSH host. Keeping
            // them when the URL changes makes Presets/Models look incomplete
            // because the UI is actually showing the previous host's cache.
            eventTask?.cancel()
            openSessions.removeAll()
            sessions = []
            workspaces = []
            archivedSessionIds = []
            agentPresets = []
            providers = []
            credentials = []
            modelCatalog = []
            plugins = []
            pendingApprovals = []
            pendingQuestions = []
            selectedWorkspaceId = nil
            selectedConversationId = nil
            mainPresentation = .welcome
            connectionGeneration += 1
            sidebarServers.removeAll { $0.server.id == activeServerID }
            Task {
                await boot()
            }
        }
    }

    private(set) var client: DshClient
    @Published private(set) var servers: [DshServer]
    @Published private(set) var activeServerID: UUID?
    @Published private(set) var sidebarServers: [ServerWorkspaceSnapshot] = []
    @Published var sessions: [SessionSummary] = []
    @Published var sessionsError: String?
    @Published var isLoadingSessions = false
    @Published var connectionInfo: String?
    @Published var isOffline = false
    @Published var showSettings = false
    @Published var showSidebar = false
    @Published var showNewChatDestination = false
    @Published var mainPresentation: MainPresentation = .welcome

    @Published var pendingApprovals: [ApprovalWait] = []
    @Published var pendingQuestions: [QuestionWait] = []

    @Published var workspaces: [Workspace] = []
    /// The host keeps archived sessions in the workspace projection even after
    /// they have been removed from the visible session list.
    @Published private(set) var archivedSessionIds: Set<String> = []
    @Published var selectedWorkspaceId: String?
    @Published var selectedConversationId: String?
    @Published var lastConversationByProject: [String: String] = [:]
    @Published var searchQuery = ""
    @Published var agentPresets: [AgentPreset] = []
    @Published var providers: [ProviderView] = []
    @Published var credentials: [CredentialView] = []
    @Published var modelCatalog: [ModelGroup] = []
    @Published var plugins: [PluginEntry] = []
    @Published var settingsError: String?
    @Published var operationError: String?
    @Published var discoveredHosts: [DiscoveredHost] = []
    @Published var isDiscovering = false
    @Published var permissionPreset: String?
    @Published var permissionRevision: Double = 0

    private var openSessions: [String: SessionModel] = [:]
    private var eventTask: Task<Void, Never>?
    private var connectionGeneration = 0
    private var pendingSidebarDestination: SidebarDestination?
    private static let serversKey = "dshServers.v1"
    private static let activeServerKey = "dshActiveServerID.v1"
    /// Used only by the App Store capture scheme. It never reaches a host and
    /// is activated explicitly with `--store-screenshot-demo <screen>`.
    private let storeScreenshotDemoScreen: String?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--store-screenshot-demo"), arguments.indices.contains(index + 1) {
            storeScreenshotDemoScreen = arguments[index + 1]
        } else {
            storeScreenshotDemoScreen = nil
        }
        let defaults = UserDefaults.standard
        let loadedServers: [DshServer]
        if storeScreenshotDemoScreen != nil {
            loadedServers = [DshServer(name: "Studio Mac", baseURLString: "https://studio-mac.example", hostID: "store-demo")]
        } else if let data = defaults.data(forKey: Self.serversKey),
                  let saved = try? JSONDecoder().decode([DshServer].self, from: data) {
            loadedServers = saved
        } else if let legacyURL = defaults.string(forKey: "dshBaseURL"), !legacyURL.isEmpty {
            loadedServers = [DshServer(name: URL(string: legacyURL)?.host ?? "DSH Server", baseURLString: legacyURL)]
        } else {
            loadedServers = []
        }
        let savedID = defaults.string(forKey: Self.activeServerKey).flatMap(UUID.init(uuidString:))
        let initialID = loadedServers.contains(where: { $0.id == savedID }) ? savedID : loadedServers.first?.id
        let stored = loadedServers.first(where: { $0.id == initialID })?.baseURLString ?? "http://127.0.0.1:3080"
        self.servers = loadedServers
        self.activeServerID = initialID
        self.baseURLString = stored
        self.client = Self.makeClient(
            baseURLString: stored,
            credentialKey: loadedServers.first(where: { $0.id == initialID })?.credentialKey
        )
        if storeScreenshotDemoScreen != nil { seedStoreScreenshotDemo() }
    }

    func boot() async {
        guard storeScreenshotDemoScreen == nil else { return }
        guard activeServerID != nil else {
            isOffline = true
            return
        }
        let generation = connectionGeneration
        await testConnection()
        guard !isOffline, generation == connectionGeneration else { return }
        await loadSessions()
        await loadWorkspaces()
        await loadAgentPresets()
        await loadProviders()
        await loadCredentials()
        await loadModelCatalog()
        await loadPermission()
        await loadPlugins()
        guard generation == connectionGeneration else { return }
        startEvents()
        updateActiveSidebarSnapshot()
        openPendingSidebarDestinationIfNeeded()
        Task { await refreshInactiveSidebarServers() }
    }

    var activeServer: DshServer? {
        servers.first { $0.id == activeServerID }
    }

    private static func makeClient(baseURLString: String, credentialKey: String?) -> DshClient {
        let url = URL(string: baseURLString) ?? URL(string: "http://127.0.0.1:3080")!
        guard let credentialKey else { return DshClient(baseURL: url) }
        return DshClient(baseURL: url) {
            await DshNetworkAuth.shared.authorization(for: credentialKey, baseURL: url)
        }
    }

    func addServer(name: String, baseURLString: String, hostID: String? = nil, credentialKey: String? = nil) {
        let trimmedURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? (URL(string: trimmedURL)?.host ?? "DSH Server") : trimmedName

        if let index = servers.firstIndex(where: {
            $0.baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ==
                trimmedURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }) {
            servers[index].name = displayName
            if let hostID { servers[index].hostID = hostID }
            if let credentialKey { servers[index].credentialKey = credentialKey }
            persistServers()
            activateServer(servers[index].id)
            return
        }

        if let hostID,
           let index = servers.firstIndex(where: { $0.hostID == hostID }) {
            servers[index].name = displayName
            servers[index].baseURLString = trimmedURL
            if let credentialKey { servers[index].credentialKey = credentialKey }
            persistServers()
            activateServer(servers[index].id)
            return
        }

        let server = DshServer(name: displayName, baseURLString: trimmedURL, hostID: hostID, credentialKey: credentialKey)
        servers.append(server)
        persistServers()
        activateServer(server.id)
    }

    func connectDiscoveredHost(_ host: DiscoveredHost) {
        addServer(name: host.label, baseURLString: host.baseURL.absoluteString, hostID: host.hostID)
    }

    func pairNetworkServer(scannedURL: URL) async throws {
        let paired = try await DshNetworkAuth.shared.pair(scannedURL: scannedURL)
        addServer(
            name: paired.result.name,
            baseURLString: paired.baseURL.absoluteString,
            hostID: paired.result.hostId,
            credentialKey: paired.result.hostId
        )
    }

    func updateServer(_ server: DshServer, name: String, baseURLString: String) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        let trimmedURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        servers[index].name = trimmedName.isEmpty ? (URL(string: trimmedURL)?.host ?? "DSH Server") : trimmedName
        servers[index].baseURLString = trimmedURL
        servers[index].hostID = nil
        persistServers()
        if activeServerID == server.id { activateServer(server.id) }
    }

    func removeServer(_ server: DshServer) {
        if let credentialKey = server.credentialKey {
            Task { await DshNetworkAuth.shared.remove(key: credentialKey) }
        }
        servers.removeAll { $0.id == server.id }
        sidebarServers.removeAll { $0.server.id == server.id }
        persistServers()
        if activeServerID == server.id { activateServer(servers.first?.id) }
    }

    func activateServer(_ id: UUID?) {
        eventTask?.cancel()
        connectionGeneration += 1
        activeServerID = id
        UserDefaults.standard.set(id?.uuidString, forKey: Self.activeServerKey)
        guard let server = activeServer else {
            resetServerState()
            return
        }
        if baseURLString != server.baseURLString {
            baseURLString = server.baseURLString
        } else {
            resetServerState()
            Task { await boot() }
        }
    }

    func openSidebarWorkspace(serverID: UUID, workspaceID: String) {
        openSidebarDestination(SidebarDestination(serverID: serverID, workspaceID: workspaceID, sessionID: nil))
    }

    func openSidebarSession(serverID: UUID, workspaceID: String?, sessionID: String) {
        openSidebarDestination(SidebarDestination(serverID: serverID, workspaceID: workspaceID, sessionID: sessionID))
    }

    private func openSidebarDestination(_ destination: SidebarDestination) {
        if destination.serverID != activeServerID {
            pendingSidebarDestination = destination
            activateServer(destination.serverID)
            return
        }
        if let workspaceID = destination.workspaceID { selectProject(workspaceID) }
        if let sessionID = destination.sessionID { selectConversation(sessionID) }
    }

    private func openPendingSidebarDestinationIfNeeded() {
        guard let destination = pendingSidebarDestination,
              destination.serverID == activeServerID else { return }
        pendingSidebarDestination = nil
        openSidebarDestination(destination)
    }

    private func persistServers() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: Self.serversKey)
        }
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

    func setDefaultAgentPreset(_ preset: String) async {
        do {
            _ = try await client.call("settings.update", payload: .object([
                "ns": .string("agent-presets"),
                "patch": .object(["default": .string(preset)]),
            ]))
            await loadAgentPresets()
            settingsError = nil
        } catch {
            settingsError = String(describing: error)
        }
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
        guard credentials.first(where: { $0.name == ref })?.writable == true else {
            settingsError = String(localized: "此凭证由主机管理，不能从远端修改")
            return
        }
        do {
            let _ = try await client.call("credentials.set", payload: .object(["ref": .string(ref), "value": .string(value)]))
            await loadCredentials()
            settingsError = nil
        } catch {
            settingsError = String(describing: error)
        }
    }

    func unsetCredential(ref: String) async {
        guard credentials.first(where: { $0.name == ref })?.writable == true else {
            settingsError = String(localized: "此凭证由主机管理，不能从远端修改")
            return
        }
        do {
            let _ = try await client.call("credentials.unset", payload: .object(["ref": .string(ref)]))
            await loadCredentials()
            settingsError = nil
        } catch {
            settingsError = String(describing: error)
        }
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
            sidebarServers.removeAll { $0.server.id == activeServerID }
        }
    }

    func loadWorkspaces() async {
        do {
            let value = try await client.call("workspace.list")
            let projection = WorkspaceListProjection(json: value)
            workspaces = projection.workspaces
            archivedSessionIds = projection.archivedSessionIds
            if let selectedConversationId, archivedSessionIds.contains(selectedConversationId) {
                self.selectedConversationId = nil
                mainPresentation = .workspace
            }
            if selectedWorkspaceId == nil || !workspaces.contains(where: { $0.workspaceId == selectedWorkspaceId }) {
                selectedWorkspaceId = workspaces.first?.workspaceId
            }
        } catch {
            // Refresh failures are intentionally non-fatal; mutation callers
            // still receive the original RPC error below.
        }
    }

    func createSession(workspaceId: String?, agentPreset: String?) async -> String? {
        var payload: [String: JSONValue] = [:]
        if let workspaceId { payload["workspaceId"] = .string(workspaceId) }
        if let agentPreset { payload["agentPreset"] = .string(agentPreset) }
        do {
            let value = try await client.call("session.create", payload: .object(payload))
            let id = value["sessionId"]?.string
            await loadSessions()
            await loadWorkspaces()
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
        conversations(in: projectId, order: .lastUpdated)
    }

    enum SessionOrder {
        case manual
        case lastUpdated
    }

    func conversations(in projectId: String, order: SessionOrder) -> [SessionSummary] {
        guard let ws = workspaces.first(where: { $0.workspaceId == projectId }) else { return [] }
        let visible = sessions.filter {
            ws.sessionIds.contains($0.sessionId) && !$0.blank && !archivedSessionIds.contains($0.sessionId)
        }
        switch order {
        case .lastUpdated:
            return visible.sorted { $0.updatedAt > $1.updatedAt }
        case .manual:
            return ws.sessionIds.compactMap { id in visible.first { $0.sessionId == id } }
        }
    }

    func selectProject(_ id: String?) {
        selectedWorkspaceId = id
        selectedConversationId = id.flatMap { lastConversationByProject[$0] }
        mainPresentation = selectedConversationId == nil ? .workspace : .conversation
    }

    func selectConversation(_ id: String) {
        guard !archivedSessionIds.contains(id) else { return }
        selectedConversationId = id
        mainPresentation = .conversation
        if let ws = workspaces.first(where: { $0.sessionIds.contains(id) }) {
            selectedWorkspaceId = ws.workspaceId
            lastConversationByProject[ws.workspaceId] = id
        }
    }

    func newChat(workspaceId: String? = nil) {
        selectedWorkspaceId = workspaceId ?? selectedWorkspaceId ?? workspaces.first?.workspaceId
        selectedConversationId = nil
        mainPresentation = .workspace
    }

    func showWelcome() {
        mainPresentation = .welcome
    }

    func requestNewChatDestination() {
        showNewChatDestination = true
    }

    func renameSession(sessionId: String, title: String) async throws {
        let _ = try await client.call("session.rename", payload: .object(["sessionId": .string(sessionId), "title": .string(title)]))
        await loadSessions()
        await loadWorkspaces()
    }

    func archiveSession(sessionId: String) async throws {
        let _ = try await client.call("workspace.archiveSession", payload: .object(["sessionId": .string(sessionId)]))
        await loadWorkspaces()
        await loadSessions()
        if selectedConversationId == sessionId {
            selectedConversationId = nil
            mainPresentation = .workspace
        }
    }

    func forkSession(sessionId: String) async {
        do {
            let value = try await client.call("session.fork", payload: .object(["sessionId": .string(sessionId)]))
            await loadSessions()
            if let forkedId = value["sessionId"]?.string ?? value["id"]?.string {
                selectConversation(forkedId)
            }
            operationError = nil
        } catch {
            operationError = String(describing: error)
        }
    }

    // Optional-return convenience for the first-message flow. Interactive
    // editors call `addWorkspace` so host errors remain visible and retryable.
    func createWorkspace(path: String) async -> String? {
        try? await addWorkspace(path: path)
    }

    func addWorkspace(path: String) async throws -> String? {
        let value = try await client.call("workspace.create", payload: .object(["path": .string(path)]))
        let wid = value["workspace"]?["workspaceId"]?.string
        await loadWorkspaces()
        if let wid {
            selectedWorkspaceId = wid
            selectedConversationId = nil
        }
        return wid
    }

    func renameWorkspace(workspaceId: String, title: String) async throws {
        let _ = try await client.call("workspace.rename", payload: .object(["workspaceId": .string(workspaceId), "title": .string(title)]))
        await loadWorkspaces()
    }

    func deleteWorkspace(workspaceId: String) async throws {
        let _ = try await client.call("workspace.delete", payload: .object(["workspaceId": .string(workspaceId)]))
        if selectedWorkspaceId == workspaceId {
            selectedWorkspaceId = nil
            selectedConversationId = nil
            mainPresentation = .workspace
        }
        await loadWorkspaces()
        await loadSessions()
    }

    var visibleSessions: [SessionSummary] {
        var result = sessions.filter { !$0.blank && !archivedSessionIds.contains($0.sessionId) }
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
            operationError = nil
        } catch {
            operationError = String(describing: error)
        }
    }

    func discoverHosts() async {
        isDiscovering = true
        defer { isDiscovering = false }
        discoveredHosts = await HostDiscovery.discover()
    }

    func testConnection() async {
        do {
            let host: HostInfo = try await client.call("host.describe", as: HostInfo.self)
            recordActiveHostIdentity(host.hostId)
            connectionInfo = "已连接 \(host.model ?? "?") @ \(host.cwd)"
            isOffline = false
            updateActiveSidebarSnapshot()
        } catch {
            connectionInfo = "连接失败: \(error)"
            isOffline = true
            sidebarServers.removeAll { $0.server.id == activeServerID }
        }
    }

    private func recordActiveHostIdentity(_ hostID: String?) {
        guard let hostID, let activeServerID,
              servers.contains(where: { $0.id == activeServerID }) else { return }
        let duplicateIDs = Set(servers.filter { $0.id != activeServerID && $0.hostID == hostID }.map(\.id))
        servers.removeAll { duplicateIDs.contains($0.id) }
        sidebarServers.removeAll { duplicateIDs.contains($0.server.id) }
        guard let updatedIndex = servers.firstIndex(where: { $0.id == activeServerID }) else { return }
        servers[updatedIndex].hostID = hostID
        persistServers()
    }

    private func resetServerState() {
        eventTask?.cancel()
        openSessions.removeAll()
        sessions = []
        workspaces = []
        archivedSessionIds = []
        agentPresets = []
        providers = []
        credentials = []
        modelCatalog = []
        plugins = []
        pendingApprovals = []
        pendingQuestions = []
        selectedWorkspaceId = nil
        selectedConversationId = nil
        connectionInfo = nil
        isOffline = activeServerID == nil
        sidebarServers.removeAll { $0.server.id == activeServerID }
        mainPresentation = .welcome
    }

    private func updateActiveSidebarSnapshot() {
        guard !isOffline, let server = activeServer else { return }
        let snapshot = ServerWorkspaceSnapshot(
            server: server,
            workspaces: workspaces,
            sessions: sessions,
            archivedSessionIds: archivedSessionIds
        )
        sidebarServers.removeAll { $0.server.id == server.id }
        sidebarServers.insert(snapshot, at: 0)
    }

    private func refreshInactiveSidebarServers() async {
        let generation = connectionGeneration
        let inactive = servers.filter { $0.id != activeServerID }
        var refreshed: [ServerWorkspaceSnapshot] = []

        for server in inactive {
            guard let url = server.url else { continue }
            let probe = DshClient(baseURL: url)
            do {
                async let sessionValue = probe.call("session.list")
                async let workspaceValue = probe.call("workspace.list")
                let sessionsJSON = try await sessionValue
                let workspaceJSON = try await workspaceValue
                let projection = WorkspaceListProjection(json: workspaceJSON)
                refreshed.append(ServerWorkspaceSnapshot(
                    server: server,
                    workspaces: projection.workspaces,
                    sessions: (sessionsJSON["items"]?.array ?? []).compactMap(SessionSummary.init(json:)),
                    archivedSessionIds: projection.archivedSessionIds
                ))
            } catch {
                // Offline hosts deliberately disappear from the sidebar.
            }
        }

        guard generation == connectionGeneration else { return }
        let active = sidebarServers.first { $0.server.id == activeServerID }
        sidebarServers = [active].compactMap { $0 } + refreshed
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
                let event = frame.payload["event"] ?? .null
                model.apply(event: event, view: frame.payload["view"])
                if event["type"]?.string == "commands/change" {
                    Task { await model.loadCommands() }
                }
            }
        case "commands/change":
            if let sessionId = frame.payload["sessionId"]?.string ?? frame.payload["agentId"]?.string,
               let model = openSessions[sessionId] {
                Task { await model.loadCommands() }
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
            Task {
                await loadSessions()
                await loadWorkspaces()
                updateActiveSidebarSnapshot()
            }
        default:
            break
        }
    }
}

private extension AppModel {
    func seedStoreScreenshotDemo() {
        let active = SessionSummary(json: .object([
            "sessionId": .string("release-check"),
            "updatedAt": .number(1_775_123_600),
            "running": .bool(true),
            "blank": .bool(false),
            "cwd": .string("~/Projects/mobile-release"),
            "agentPreset": .string("code"),
            "projections": .object(["values": .object(["title": .string("Prepare the iOS release")])]),
        ]))!
        let review = SessionSummary(json: .object([
            "sessionId": .string("review-queue"),
            "updatedAt": .number(1_775_122_900),
            "running": .bool(false),
            "blank": .bool(false),
            "cwd": .string("~/Projects/api-service"),
            "agentPreset": .string("standard"),
            "projections": .object(["values": .object(["title": .string("Review the deployment queue")])]),
        ]))!
        let tests = SessionSummary(json: .object([
            "sessionId": .string("test-report"),
            "updatedAt": .number(1_775_120_100),
            "running": .bool(false),
            "blank": .bool(false),
            "cwd": .string("~/Projects/product-site"),
            "agentPreset": .string("minimal"),
            "projections": .object(["values": .object(["title": .string("Summarize today’s test report")])]),
        ]))!

        sessions = [active, review, tests]
        workspaces = [
            Workspace(json: .object([
                "workspaceId": .string("mobile-release"),
                "path": .string("~/Projects/mobile-release"),
                "title": .string("Mobile release"),
                "sessionIds": .array([.string(active.sessionId)]),
                "updatedAt": .string("Today"),
            ]))!,
            Workspace(json: .object([
                "workspaceId": .string("api-service"),
                "path": .string("~/Projects/api-service"),
                "title": .string("API service"),
                "sessionIds": .array([.string(review.sessionId)]),
                "updatedAt": .string("Today"),
            ]))!,
            Workspace(json: .object([
                "workspaceId": .string("product-site"),
                "path": .string("~/Projects/product-site"),
                "title": .string("Product site"),
                "sessionIds": .array([.string(tests.sessionId)]),
                "updatedAt": .string("Yesterday"),
            ]))!,
        ]
        agentPresets = [
            AgentPreset(json: .object(["id": .string("standard"), "trust": .string("system"), "isDefault": .bool(true)]))!,
            AgentPreset(json: .object(["id": .string("code"), "trust": .string("system"), "isDefault": .bool(false)]))!,
        ]
        credentials = [
            CredentialView(name: "DEEPSEEK_API_KEY", configured: true, writable: false),
            CredentialView(name: "PI_API_KEY", configured: true, writable: false),
        ]
        providers = [ProviderView(json: .object([
            "provider": .string("deepseek"),
            "displayName": .string("DeepSeek"),
            "settingsNs": .string("deepseek"),
            "active": .bool(true),
        ]))!]
        discoveredHosts = [
            DiscoveredHost(baseURL: URL(string: "http://studio-mac.local:3080")!, label: "Studio Mac", info: nil),
            DiscoveredHost(baseURL: URL(string: "https://build-server.example")!, label: "Build server", info: nil),
        ]
        permissionPreset = "read-only"
        selectedWorkspaceId = workspaces.first?.workspaceId
        connectionInfo = "Connected securely"
        isOffline = false

        switch storeScreenshotDemoScreen {
        case "sidebar":
            mainPresentation = .workspace
            showSidebar = true
        case "settings":
            mainPresentation = .workspace
            showSettings = true
        default:
            mainPresentation = .welcome
        }
    }
}
