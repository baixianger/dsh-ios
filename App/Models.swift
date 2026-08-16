import Foundation

extension JSONValue {
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var double: Double? { if case .number(let n) = self { return n }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    subscript(_ key: String) -> JSONValue? { object?[key] }
}

struct SessionSummary: Identifiable {
    let sessionId: String
    let updatedAt: Double
    var running: Bool
    let blank: Bool
    let cwd: String?
    let agentPreset: String?
    let projections: JSONValue?

    var id: String { sessionId }

    var title: String? { projections?["values"]?["title"]?.string }
    var planActive: Bool { projections?["values"]?["plan"]?["active"]?.bool ?? false }
    var planPending: Bool { projections?["values"]?["plan"]?["pending"]?.bool ?? false }
    var sessionStats: JSONValue? { projections?["values"]?["sessionStats"] }
    var tokenUsage: JSONValue? { projections?["values"]?["tokenUsage"] }
    var goal: JSONValue? { projections?["values"]?["goal"] }

    init?(json: JSONValue) {
        guard let sid = json["sessionId"]?.string else { return nil }
        self.sessionId = sid
        self.updatedAt = json["updatedAt"]?.double ?? 0
        self.running = json["running"]?.bool ?? false
        self.blank = json["blank"]?.bool ?? false
        self.cwd = json["cwd"]?.string
        self.agentPreset = json["agentPreset"]?.string
        self.projections = json["projections"]
    }
}

struct ChatItem: Identifiable, Equatable {
    enum Role { case user, assistant, tool, notice }
    let id: String
    var role: Role
    var text: String
    var reasoning: String? = nil
    var toolName: String? = nil
    var toolArgs: String? = nil
    var isToolResult: Bool = false
    var readCard: ReadCard? = nil
    var diffCard: DiffCard? = nil
    var isStreaming: Bool = false
    var imageAttachmentId: String? = nil
    var imageData: Data? = nil
    var messageId: String? = nil
}

struct PluginEntry: Identifiable {
    let entryId: String
    let moduleName: String
    let enabled: Bool
    let fiberPhase: String?
    var id: String { entryId }

    init?(json: JSONValue) {
        guard let eid = json["entryId"]?.string else { return nil }
        self.entryId = eid
        self.moduleName = json["moduleName"]?.string ?? ""
        self.enabled = json["enabled"]?.bool ?? false
        self.fiberPhase = json["fiberPhase"]?.string
    }
}

struct MessageFeedbackItem: Identifiable {
    let messageId: String
    let rating: String
    let note: String?
    let version: String
    var id: String { messageId }

    init?(json: JSONValue) {
        guard let mid = json["messageId"]?.string else { return nil }
        self.messageId = mid
        self.rating = json["rating"]?.string ?? ""
        self.note = json["note"]?.string
        self.version = json["version"]?.string ?? ""
    }
}

struct SubagentEntry: Identifiable {
    let id: String
    let mode: String
    let activity: String
    let label: String?
    let isDiagnostic: Bool
    let reason: String?

    init?(json: JSONValue) {
        guard let id = json["id"]?.string else { return nil }
        self.id = id
        if json["kind"]?.string == "diagnostic" {
            self.isDiagnostic = true
            self.mode = ""
            self.activity = "unavailable"
            self.label = nil
            self.reason = json["reason"]?.string
        } else {
            self.isDiagnostic = false
            self.mode = json["mode"]?.string ?? ""
            self.activity = json["activity"]?.string ?? "inactive"
            self.label = json["label"]?.string
            self.reason = nil
        }
    }
}

struct JobView: Identifiable {
    let id: String
    let kind: String
    let label: String
    let status: String
    let detail: String?
    let startedAt: Double
    let finishedAt: Double?

    init?(json: JSONValue) {
        guard let id = json["id"]?.string else { return nil }
        self.id = id
        self.kind = json["kind"]?.string ?? ""
        self.label = json["label"]?.string ?? ""
        self.status = json["status"]?.string ?? "running"
        self.detail = json["detail"]?.string
        self.startedAt = json["startedAt"]?.double ?? 0
        self.finishedAt = json["finishedAt"]?.double
    }
}

struct ModelInfo: Identifiable {
    let id: String
    let name: String
    let efforts: [String]
}

struct ModelGroup: Identifiable {
    let id: String
    let name: String
    let models: [ModelInfo]

    init?(json: JSONValue) {
        guard let id = json["id"]?.string else { return nil }
        self.id = id
        self.name = json["name"]?.string ?? id
        self.models = (json["models"]?.array ?? []).compactMap { m in
            guard let mid = m["id"]?.string else { return nil }
            let efforts = m["reasoning"]?["efforts"]?.array?.compactMap { $0["id"]?.string } ?? []
            return ModelInfo(id: mid, name: m["name"]?.string ?? mid, efforts: efforts)
        }
    }
}

struct GoalState: Equatable {
    let id: String
    let revision: Double
    let objective: String
    let phase: String
    let roundsStarted: Double
    let maxGoalRounds: Double
    let blockedReason: String?

    init?(json: JSONValue) {
        guard let id = json["id"]?.string,
              let objective = json["objective"]?.string,
              let phase = json["phase"]?.string else { return nil }
        self.id = id
        self.revision = json["revision"]?.double ?? 0
        self.objective = objective
        self.phase = phase
        self.roundsStarted = json["roundsStarted"]?.double ?? 0
        self.maxGoalRounds = json["maxGoalRounds"]?.double ?? 0
        self.blockedReason = json["blockedReason"]?["message"]?.string
    }
}

struct AgentPreset: Identifiable {
    let id: String
    let trust: String
    let isDefault: Bool
    let name: String?
    let description: String?
    var displayName: String { name ?? id }

    init?(json: JSONValue) {
        guard let id = json["id"]?.string else { return nil }
        self.id = id
        self.trust = json["trust"]?.string ?? "user"
        self.isDefault = json["isDefault"]?.bool ?? false
        self.name = json["name"]?.string
        self.description = json["description"]?.string
    }
}

struct SkillEntry: Identifiable {
    let name: String
    let description: String
    let whenToUse: String?
    var id: String { name }

    init?(json: JSONValue) {
        guard let name = json["name"]?.string else { return nil }
        self.name = name
        self.description = json["description"]?.string ?? ""
        self.whenToUse = json["whenToUse"]?.string
    }
}

struct CredentialView: Identifiable {
    let name: String
    let configured: Bool
    let writable: Bool
    var id: String { name }
}

struct ProviderView: Identifiable {
    let provider: String
    let displayName: String
    let settingsNs: String
    let active: Bool
    var id: String { provider }

    init?(json: JSONValue) {
        guard let provider = json["provider"]?.string else { return nil }
        self.provider = provider
        self.displayName = json["displayName"]?.string ?? provider
        self.settingsNs = json["settingsNs"]?.string ?? ""
        self.active = json["active"]?.bool ?? false
    }
}

struct Workspace: Identifiable {
    let workspaceId: String
    let path: String
    let title: String
    let sessionIds: [String]
    let updatedAt: String

    var id: String { workspaceId }

    init?(json: JSONValue) {
        guard let id = json["workspaceId"]?.string,
              let path = json["path"]?.string else { return nil }
        self.workspaceId = id
        self.path = path
        self.title = json["title"]?.string ?? (path as NSString).lastPathComponent
        self.sessionIds = (json["sessionIds"]?.array ?? []).compactMap { $0.string }
        self.updatedAt = json["updatedAt"]?.string ?? ""
    }
}

struct ApprovalWait: Identifiable {
    let rpcId: String
    let sessionId: String
    let approvalId: String
    let toolName: String
    let callId: String?
    let payload: JSONValue
    var id: String { approvalId }

    init?(rpcId: String, payload: JSONValue) {
        guard let sessionId = payload["sessionId"]?.string,
              let approvalId = payload["approvalId"]?.string else { return nil }
        self.rpcId = rpcId
        self.sessionId = sessionId
        self.approvalId = approvalId
        self.toolName = payload["toolName"]?.string ?? "tool"
        self.callId = payload["callId"]?.string
        self.payload = payload
    }
}

struct QuestionWait: Identifiable {
    let rpcId: String
    let sessionId: String
    let payload: JSONValue
    var id: String { rpcId }

    init?(rpcId: String, payload: JSONValue) {
        guard let sessionId = payload["sessionId"]?.string else { return nil }
        self.rpcId = rpcId
        self.sessionId = sessionId
        self.payload = payload
    }
}

struct ReadLine: Equatable {
    let number: Double?
    let text: String
}

struct ReadCard: Equatable {
    let label: String
    let lang: String?
    let totalLines: Double?
    let lines: [ReadLine]

    init?(json: JSONValue, sessionCwd: String?) {
        guard json["card"]?.string == "read" else { return nil }
        let title = json["title"]?.string
        let path = json["path"]?.string
        if let title, !title.isEmpty {
            self.label = title
        } else if let path {
            self.label = Self.relativize(path, cwd: sessionCwd)
        } else {
            self.label = "文件"
        }
        self.lang = json["lang"]?.string
        self.totalLines = json["totalLines"]?.double
        self.lines = (json["lines"]?.array ?? []).map { l in
            ReadLine(number: l["number"]?.double, text: l["text"]?.string ?? "")
        }
    }

    private static func relativize(_ path: String, cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return path }
        if path.hasPrefix(cwd + "/") { return String(path.dropFirst(cwd.count + 1)) }
        return path
    }
}

struct DiffHunk: Equatable {
    let path: String
    let oldText: String?
    let newText: String
}

struct DiffCard: Equatable {
    let diffs: [DiffHunk]

    init?(json: JSONValue) {
        guard json["card"]?.string == "diff" else { return nil }
        let hunks = (json["diffs"]?.array ?? []).compactMap { h -> DiffHunk? in
            guard let path = h["path"]?.string, let newText = h["newText"]?.string else { return nil }
            return DiffHunk(path: path, oldText: h["oldText"]?.string, newText: newText)
        }
        guard !hunks.isEmpty else { return nil }
        self.diffs = hunks
    }
}
