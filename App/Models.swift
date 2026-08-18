import Foundation

struct DshServer: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var baseURLString: String
    var hostID: String?
    var credentialKey: String?

    init(id: UUID = UUID(), name: String, baseURLString: String, hostID: String? = nil, credentialKey: String? = nil) {
        self.id = id
        self.name = name
        self.baseURLString = baseURLString
        self.hostID = hostID
        self.credentialKey = credentialKey
    }

    var url: URL? {
        URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    enum CodingKeys: String, CodingKey { case id, name, baseURLString, hostID, credentialKey }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        baseURLString = try values.decode(String.self, forKey: .baseURLString)
        hostID = try values.decodeIfPresent(String.self, forKey: .hostID)
        credentialKey = try values.decodeIfPresent(String.self, forKey: .credentialKey)
    }
}

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

struct SessionCommand: Identifiable, Equatable {
    let name: String
    let description: String
    let inputHint: String?
    var insertion: String { "/" + name + ((inputHint?.isEmpty == false) ? " " : "") }

    var id: String { name }

    init?(json: JSONValue) {
        guard let name = json["name"]?.string, !name.isEmpty else { return nil }
        self.name = name.hasPrefix("/") ? String(name.dropFirst()) : name
        self.description = json["description"]?.string ?? ""
        self.inputHint = json["inputHint"]?.string ?? json["input"]?["hint"]?.string
    }
}

struct WorkspaceListProjection {
    let workspaces: [Workspace]
    let archivedSessionIds: Set<String>

    init(json: JSONValue) {
        workspaces = (json["items"]?.array ?? []).compactMap { Workspace(json: $0) }
        archivedSessionIds = Set((json["archivedSessionIds"]?.array ?? []).compactMap { $0.string })
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

enum TrajectoryKind: String, CaseIterable {
    case user
    case assistant
    case tool
    case subtool
    case context
    case compaction
    case system
    case error
}

struct TrajectoryRecord: Identifiable, Equatable {
    let seq: Int
    let time: Double
    let eventType: String
    let turn: Int?
    let step: Int?
    let kind: TrajectoryKind
    let title: String
    let preview: String
    let durationMilliseconds: Double?
    let isError: Bool
    let data: JSONValue
    let view: JSONValue?

    var id: String { "\(eventType)-\(seq)" }

    var searchableText: String {
        [eventType, title, preview, data.prettyPrinted]
            .joined(separator: " ")
            .localizedLowercase
    }
}

struct TrajectoryTurn: Identifiable, Equatable {
    let turn: Int?
    let records: [TrajectoryRecord]

    var id: String { turn.map { "turn-\($0)" } ?? "session" }
}

enum TrajectoryBuilder {
    static func build(_ entries: [JSONValue]) -> [TrajectoryRecord] {
        let events = entries.compactMap { entry -> (event: JSONValue, view: JSONValue?)? in
            guard let type = entry["event"]?["type"]?.string, !type.isEmpty else { return nil }
            return (entry["event"] ?? .null, entry["view"])
        }

        var toolResults: [String: JSONValue] = [:]
        var toolResultViews: [String: JSONValue] = [:]
        var stepStarts: [String: Double] = [:]
        var currentTurn: Int?

        for pair in events {
            let event = pair.event
            let type = event["type"]?.string ?? ""
            let data = event["data"] ?? .null
            if type == "tool/result", let callId = resultCallId(data) {
                toolResults[callId] = event
                if let view = pair.view { toolResultViews[callId] = view }
            } else if type == "step/start" {
                if let turn = integer(data["turn"]), let step = integer(data["step"]) {
                    stepStarts["\(turn):\(step)"] = event["time"]?.double
                }
            }
        }

        var records: [TrajectoryRecord] = []
        var previousTime: Double?
        for pair in events {
            let event = pair.event
            let type = event["type"]?.string ?? ""
            let data = event["data"] ?? .null
            let time = event["time"]?.double ?? previousTime ?? 0
            if type == "turn/start" { currentTurn = integer(data["turn"]) }
            let turn = integer(data["turn"]) ?? currentTurn
            let step = integer(data["step"])

            let record: TrajectoryRecord?
            switch type {
            case "user/message":
                record = make(event, view: pair.view, kind: .user, title: "User message", preview: messageText(data), turn: turn, step: step)
            case "assistant/message":
                let content = data["message"]?["content"] ?? .null
                let output = textBlocks(content)
                let reasoning = reasoningBlocks(content)
                let start = turn.flatMap { t in step.map { stepStarts["\(t):\($0)"] } } ?? previousTime
                record = make(
                    event,
                    view: pair.view,
                    kind: .assistant,
                    title: "Assistant",
                    preview: output.isEmpty ? reasoning : output,
                    turn: turn,
                    step: step,
                    duration: duration(from: start, to: time)
                )
            case "tool/call":
                let callId = data["callId"]?.string ?? data["id"]?.string
                let name = data["name"]?.string ?? "Tool call"
                let args = data["arguments"]?.string ?? data["arguments"]?.prettyPrinted ?? ""
                let result = callId.flatMap { toolResults[$0] }
                let resultTime = result?["time"]?.double
                let isError = result?["data"]?["error"] != nil
                record = make(
                    event,
                    view: callId.flatMap { toolResultViews[$0] } ?? pair.view,
                    kind: .tool,
                    title: name,
                    preview: args,
                    turn: turn,
                    step: step,
                    duration: duration(from: time, to: resultTime),
                    isError: isError
                )
            case "tool/result":
                record = resultCallId(data) == nil
                    ? make(event, view: pair.view, kind: .tool, title: "Tool result", preview: toolResultText(data), turn: turn, step: step)
                    : nil
            case "tool/code-dispatch-start", "tool/code-dispatch":
                record = make(
                    event,
                    view: pair.view,
                    kind: .subtool,
                    title: data["name"]?.string ?? "Code dispatch",
                    preview: data["arguments"]?.prettyPrinted ?? "",
                    turn: turn,
                    step: step
                )
            case "request/header":
                record = make(event, view: pair.view, kind: .context, title: "Request context", preview: requestPreview(data), turn: turn, step: step)
            case "compaction/start", "compaction/end":
                record = make(event, view: pair.view, kind: .compaction, title: "Compaction", preview: data["summary"]?.string ?? "", turn: turn, step: step)
            case "session/end":
                record = make(event, view: pair.view, kind: .system, title: "Session ended", preview: "", turn: turn, step: step)
            case "turn/end":
                if data["error"] != nil {
                    record = make(event, view: pair.view, kind: .error, title: "Turn error", preview: data["error"]?.prettyPrinted ?? "", turn: turn, step: step, isError: true)
                } else {
                    record = nil
                }
                currentTurn = nil
            default:
                record = nil
            }
            if let record { records.append(record) }
            previousTime = time
        }
        return records.sorted { $0.seq < $1.seq }
    }

    static func group(_ records: [TrajectoryRecord]) -> [TrajectoryTurn] {
        var order: [Int?] = []
        var grouped: [Int?: [TrajectoryRecord]] = [:]
        for record in records {
            if grouped[record.turn] == nil { order.append(record.turn) }
            grouped[record.turn, default: []].append(record)
        }
        return order.map { TrajectoryTurn(turn: $0, records: grouped[$0] ?? []) }
    }

    private static func make(
        _ event: JSONValue,
        view: JSONValue?,
        kind: TrajectoryKind,
        title: String,
        preview: String,
        turn: Int?,
        step: Int?,
        duration: Double? = nil,
        isError: Bool = false
    ) -> TrajectoryRecord {
        let compact = preview.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return TrajectoryRecord(
            seq: integer(event["seq"]) ?? 0,
            time: event["time"]?.double ?? 0,
            eventType: event["type"]?.string ?? "event",
            turn: turn,
            step: step,
            kind: kind,
            title: title,
            preview: String(compact.prefix(512)),
            durationMilliseconds: duration,
            isError: isError,
            data: event["data"] ?? .null,
            view: view
        )
    }

    private static func integer(_ value: JSONValue?) -> Int? {
        value?.double.map(Int.init)
    }

    private static func duration(from start: Double?, to end: Double?) -> Double? {
        guard let start, let end, start.isFinite, end.isFinite else { return nil }
        return max(0, end - start)
    }

    private static func resultCallId(_ data: JSONValue) -> String? {
        data["message"]?["source"]?["callId"]?.string ?? data["callId"]?.string
    }

    private static func messageText(_ data: JSONValue) -> String {
        textBlocks(data["content"] ?? .null)
    }

    // Trajectory parsing is intentionally self-contained. SessionModel is
    // main-actor isolated because it drives the UI, while these transforms are
    // pure and can safely run outside that actor.
    private static func textBlocks(_ content: JSONValue) -> String {
        guard let blocks = content.array else { return "" }
        return blocks.compactMap { block in
            block["type"]?.string == "text" ? block["text"]?.string : nil
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private static func reasoningBlocks(_ content: JSONValue) -> String {
        guard let blocks = content.array else { return "" }
        return blocks.compactMap { block in
            block["type"]?.string == "reasoning" ? block["text"]?.string : nil
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private static func toolResultText(_ data: JSONValue) -> String {
        let text = textBlocks(data["message"]?["content"] ?? .null)
        let error = data["error"]?["message"]?.string ?? data["error"]?["name"]?.string
        return error.map { text.isEmpty ? $0 : text + "\n" + $0 } ?? text
    }

    private static func requestPreview(_ data: JSONValue) -> String {
        data["prompt"]?["messages"]?.array?.last?["content"]?.prettyPrinted
            ?? data["prompt"]?.prettyPrinted
            ?? ""
    }
}

enum TranscriptEntry: Identifiable {
    case message(ChatItem)
    case activity(id: String, reasoning: String?, tools: [ChatItem])

    var id: String {
        switch self {
        case .message(let item):
            item.id
        case .activity(let id, _, _):
            id
        }
    }

    var message: ChatItem? {
        guard case .message(let item) = self else { return nil }
        return item
    }
}

enum TranscriptBuilder {
    static func build(from items: [ChatItem]) -> [TranscriptEntry] {
        var entries: [TranscriptEntry] = []
        var index = items.startIndex

        while index < items.endIndex {
            let item = items[index]

            if item.role == .assistant,
               let reasoning = item.reasoning,
               !reasoning.isEmpty {
                let toolsStart = items.index(after: index)
                let toolsEnd = endOfToolRun(in: items, startingAt: toolsStart)

                if toolsStart < toolsEnd {
                    let tools = Array(items[toolsStart..<toolsEnd])
                    entries.append(
                        .activity(
                            id: "activity-\(item.id)",
                            reasoning: reasoning,
                            tools: tools
                        )
                    )

                    var response = item
                    response.reasoning = nil
                    if !response.text.isEmpty || response.isStreaming || response.imageAttachmentId != nil {
                        entries.append(.message(response))
                    }

                    index = toolsEnd
                    continue
                }
            }

            if item.role == .tool {
                let toolsEnd = endOfToolRun(in: items, startingAt: index)
                let tools = Array(items[index..<toolsEnd])
                entries.append(
                    .activity(
                        id: "tools-\(item.id)",
                        reasoning: nil,
                        tools: tools
                    )
                )
                index = toolsEnd
                continue
            }

            entries.append(.message(item))
            index = items.index(after: index)
        }

        return entries
    }

    private static func endOfToolRun(in items: [ChatItem], startingAt start: Int) -> Int {
        var end = start
        while end < items.endIndex, items[end].role == .tool {
            end = items.index(after: end)
        }
        return end
    }
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

struct ModelEffort: Identifiable {
    let id: String
    let name: String
    let description: String?
}

struct ModelReasoning {
    let efforts: [ModelEffort]
    let defaultEffort: String?
}

struct ModelInfo: Identifiable {
    let id: String
    let name: String
    let description: String?
    let reasoning: ModelReasoning?
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
            let reasoning = m["reasoning"].flatMap { value -> ModelReasoning? in
                guard value.object != nil else { return nil }
                let efforts = (value["efforts"]?.array ?? []).compactMap { effort -> ModelEffort? in
                    guard let effortId = effort["id"]?.string else { return nil }
                    return ModelEffort(
                        id: effortId,
                        name: effort["name"]?.string ?? effortId,
                        description: effort["description"]?.string
                    )
                }
                return ModelReasoning(
                    efforts: efforts,
                    defaultEffort: value["defaultEffort"]?.string
                )
            }
            return ModelInfo(
                id: mid,
                name: m["name"]?.string ?? mid,
                description: m["description"]?.string,
                reasoning: reasoning
            )
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
    var displayName: String {
        // DSH Web localizes shipped presets from their stable ids instead of
        // trusting host metadata. Keep custom preset names untouched.
        guard trust == "system" else { return name ?? id }
        return switch id {
        case "standard": String(localized: "标准模式")
        case "code": String(localized: "PTC 编程模式")
        case "minimal": String(localized: "极简模式")
        case "cordis": String(localized: "创造模式")
        default: name ?? id
        }
    }

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
