import Foundation
import Combine

@MainActor
final class SessionModel: ObservableObject {
    let sessionId: String
    private let client: DshClient

    var summary: SessionSummary?
    @Published var items: [ChatItem] = []
    @Published var isLoading = false
    @Published var historyError: String?
    @Published var isRunning = false
    @Published var sendError: String?

    @Published var modelGroups: [ModelGroup] = []
    @Published var currentProvider: String?
    @Published var currentModelName: String?
    @Published var currentEffort: String?
    @Published var subagents: [SubagentEntry] = []
    @Published var jobs: [JobView] = []
    @Published var skills: [SkillEntry] = []
    @Published var draft = ""
    @Published var goal: GoalState?
    @Published var stats: JSONValue?
    @Published var tokenUsage: JSONValue?
    @Published var planActive = false
    @Published var feedbackByMessage: [String: MessageFeedbackItem] = [:]

    private var streamingItemID: String?

    private var sessionCwd: String? { summary?.cwd }

    init(sessionId: String, client: DshClient, summary: SessionSummary? = nil) {
        self.sessionId = sessionId
        self.client = client
        self.summary = summary
        self.goal = summary?.goal.flatMap { GoalState(json: $0) }
        self.stats = summary?.sessionStats
        self.tokenUsage = summary?.tokenUsage
        self.planActive = summary?.planActive ?? false
    }

    func loadHistory() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let value = try await client.call("session.history", payload: .object(["sessionId": .string(sessionId)]))
            items = Self.foldHistory(value, sessionCwd: sessionCwd)
            await hydrateImages()
            if let values = value["projections"]?["values"] {
                stats = values["sessionStats"]
                tokenUsage = values["tokenUsage"]
                goal = values["goal"].flatMap { GoalState(json: $0) }
                planActive = values["plan"]?["active"]?.bool ?? false
            }
            historyError = nil
        } catch {
            historyError = String(describing: error)
        }
    }

    func loadModels() async {
        do {
            let value = try await client.call("session.models", payload: .object(["sessionId": .string(sessionId)]))
            currentProvider = value["current"]?["provider"]?.string
            currentModelName = value["current"]?["model"]?.string
            currentEffort = value["current"]?["reasoningEffort"]?.string
            modelGroups = (value["groups"]?.array ?? []).compactMap { ModelGroup(json: $0) }
        } catch {}
    }

    func selectModel(provider: String, model: String, effort: String?) async {
        var payload: [String: JSONValue] = [
            "sessionId": .string(sessionId),
            "provider": .string(provider),
            "model": .string(model),
        ]
        if let effort { payload["reasoningEffort"] = .string(effort) }
        do {
            let value = try await client.call("session.selectModel", payload: .object(payload))
            currentProvider = value["selected"]?["provider"]?.string ?? provider
            currentModelName = value["selected"]?["model"]?.string ?? model
            currentEffort = value["selected"]?["reasoningEffort"]?.string ?? effort
        } catch {}
    }

    func loadSubagentHistory(childSessionId: String, mode: String) async -> [ChatItem]? {
        do {
            let value = try await client.call("subagent.history", payload: .object([
                "parentSessionId": .string(sessionId),
                "childSessionId": .string(childSessionId),
                "mode": .string(mode),
            ]))
            return Self.foldHistory(value, sessionCwd: sessionCwd)
        } catch {
            return nil
        }
    }

    func promptSubagent(childSessionId: String, text: String) async {
        do {
            let _ = try await client.call("subagent.prompt", payload: .object([
                "parentSessionId": .string(sessionId),
                "childSessionId": .string(childSessionId),
                "mode": .string("continuable"),
                "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            ]))
        } catch {}
    }

    func interruptSubagent(childSessionId: String) async {
        do {
            let _ = try await client.call("subagent.interrupt", payload: .object([
                "parentSessionId": .string(sessionId),
                "childSessionId": .string(childSessionId),
                "mode": .string("continuable"),
            ]))
        } catch {}
    }

    func loadSkills() async {
        do {
            let value = try await client.call("skill.list", payload: .object(["sessionId": .string(sessionId)]))
            skills = (value["skills"]?.array ?? []).compactMap { SkillEntry(json: $0) }
        } catch {}
    }

    func loadSubagents() async {
        do {
            let value = try await client.call("subagent.list", payload: .object(["parentSessionId": .string(sessionId)]))
            subagents = (value["entries"]?.array ?? []).compactMap { SubagentEntry(json: $0) }
        } catch {}
    }

    func fetchImageData(attachmentId: String) async -> Data? {
        do {
            let value = try await client.call("session.attachment", payload: .object(["sessionId": .string(sessionId), "attachmentId": .string(attachmentId)]))
            if let b64 = value["data"]?.string {
                return Data(base64Encoded: b64)
            }
        } catch {}
        return nil
    }

    func hydrateImages() async {
        for i in items.indices {
            if let aid = items[i].imageAttachmentId, items[i].imageData == nil {
                items[i].imageData = await fetchImageData(attachmentId: aid)
            }
        }
    }

    func export() async -> URL? {
        do {
            let data = try await client.exportSession(sessionId: sessionId)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-session-\(sessionId).zip")
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    func editMessage(messageId: String, text: String) async {
        do {
            let _ = try await client.call("session.updateQueue", payload: .object([
                "sessionId": .string(sessionId),
                "itemId": .string(messageId),
                "action": .object(["kind": .string("edit"), "content": .array([.object(["type": .string("text"), "text": .string(text)])])]),
            ]))
        } catch {}
    }

    func steerMessage(messageId: String) async {
        do {
            let _ = try await client.call("session.updateQueue", payload: .object([
                "sessionId": .string(sessionId),
                "itemId": .string(messageId),
                "action": .object(["kind": .string("steer")]),
            ]))
        } catch {}
    }

    func removeMessage(messageId: String) async {
        do {
            let _ = try await client.call("session.updateQueue", payload: .object([
                "sessionId": .string(sessionId),
                "itemId": .string(messageId),
                "action": .object(["kind": .string("remove")]),
            ]))
        } catch {}
    }

    func cancel() async {
        do {
            let _ = try await client.call("session.cancel", payload: .object(["sessionId": .string(sessionId)]))
        } catch {}
    }

    func send(_ text: String, image: (data: String, mediaType: String)? = nil) async {
        var content: [JSONValue] = []
        if let image {
            content.append(.object(["type": .string("image"), "mediaType": .string(image.mediaType), "data": .string(image.data)]))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            content.append(.object(["type": .string("text"), "text": .string(text)]))
        }
        guard !content.isEmpty else { return }
        do {
            let _ = try await client.call("session.prompt", payload: .object([
                "sessionId": .string(sessionId),
                "mode": .string("queue"),
                "content": .array(content),
            ]))
            sendError = nil
        } catch {
            sendError = String(describing: error)
        }
    }

    // MARK: feedback

    func loadFeedback() async {
        do {
            let value = try await client.callRemote("messageFeedback", "list", args: .object(["request": .object(["sessionId": .string(sessionId)])]))
            guard value["ok"]?.bool == true else { return }
            let items = value["value"]?["items"]?.array ?? []
            var map: [String: MessageFeedbackItem] = [:]
            for item in items {
                if let f = MessageFeedbackItem(json: item) { map[f.messageId] = f }
            }
            feedbackByMessage = map
        } catch {}
    }

    func toggleFeedback(messageId: String, rating: String) async {
        let current = feedbackByMessage[messageId]
        if current?.rating == rating {
            await deleteFeedback(messageId: messageId, ifVersion: current?.version ?? "")
        } else {
            await putFeedback(messageId: messageId, rating: rating, note: current?.note, ifVersion: current?.version)
        }
    }

    func setFeedbackNote(messageId: String, note: String) async {
        guard let current = feedbackByMessage[messageId], !current.rating.isEmpty else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            await putFeedback(messageId: messageId, rating: current.rating, note: nil, ifVersion: current.version)
        } else {
            await putFeedback(messageId: messageId, rating: current.rating, note: trimmed, ifVersion: current.version)
        }
    }

    private func putFeedback(messageId: String, rating: String, note: String?, ifVersion: String?) async {
        var request: [String: JSONValue] = [
            "sessionId": .string(sessionId),
            "messageId": .string(messageId),
            "rating": .string(rating),
            "ifVersion": ifVersion.map { .string($0) } ?? .null,
        ]
        if let note { request["note"] = .string(note) }
        do {
            let value = try await client.callRemote("messageFeedback", "put", args: .object(["request": .object(request)]))
            if value["ok"]?.bool == true, let item = value["value"], let f = MessageFeedbackItem(json: item) {
                feedbackByMessage[messageId] = f
            } else if value["ok"]?.bool == false {
                await loadFeedback()
            }
        } catch {}
    }

    private func deleteFeedback(messageId: String, ifVersion: String) async {
        do {
            let value = try await client.callRemote("messageFeedback", "delete", args: .object(["request": .object([
                "sessionId": .string(sessionId),
                "messageId": .string(messageId),
                "ifVersion": .string(ifVersion),
            ])]))
            if value["ok"]?.bool == true {
                feedbackByMessage.removeValue(forKey: messageId)
            } else if value["ok"]?.bool == false {
                await loadFeedback()
            }
        } catch {}
    }

    // MARK: goals

    func createGoal(objective: String, maxGoalRounds: Int? = nil) async {
        var payload: [String: JSONValue] = ["sessionId": .string(sessionId), "objective": .string(objective)]
        if let maxGoalRounds { payload["maxGoalRounds"] = .number(Double(maxGoalRounds)) }
        do { let _ = try await client.call("goal.create", payload: .object(payload)) } catch {}
    }

    func editGoal(objective: String, maxGoalRounds: Int?) async {
        guard let goal else { return }
        let ref = JSONValue.object(["id": .string(goal.id), "revision": .number(goal.revision)])
        var payload: [String: JSONValue] = ["sessionId": .string(sessionId), "ref": ref, "objective": .string(objective)]
        if let maxGoalRounds { payload["maxGoalRounds"] = .number(Double(maxGoalRounds)) }
        do { let _ = try await client.call("goal.edit", payload: .object(payload)) } catch {}
    }

    func pauseGoal() async { await goalAction("goal.pause") }
    func resumeGoal() async { await goalAction("goal.resume") }
    func completeGoal() async { await goalAction("goal.complete") }
    func clearGoal() async { await goalAction("goal.clear") }

    private func goalAction(_ method: String) async {
        guard let goal else { return }
        let ref = JSONValue.object(["id": .string(goal.id), "revision": .number(goal.revision)])
        do {
            let _ = try await client.call(method, payload: .object(["sessionId": .string(sessionId), "ref": ref]))
        } catch {}
    }

    // MARK: live updates

    func setJobs(_ json: JSONValue) {
        jobs = (json.array ?? []).compactMap { JobView(json: $0) }
    }

    func updateProjection(key: String, value: JSONValue) {
        switch key {
        case "goal": goal = GoalState(json: value)
        case "sessionStats": stats = value
        case "tokenUsage": tokenUsage = value
        case "plan": planActive = value["active"]?.bool ?? false
        default: break
        }
    }

    func apply(event: JSONValue, view: JSONValue? = nil) {
        let type = event["type"]?.string
        let data = event["data"] ?? .null
        let seq = event["seq"]?.double ?? 0
        switch type {
        case "user/message":
            if data["source"]?["kind"]?.string == "user" {
                let text = Self.textBlocks(data["content"] ?? .null)
                if !text.isEmpty {
                    items.append(ChatItem(id: "u-\(seq)", role: .user, text: text, messageId: data["id"]?.string))
                }
                for aid in Self.imageAttachmentIds(data["content"] ?? .null) {
                    items.append(ChatItem(id: "img-\(seq)-\(aid)", role: .user, text: "", imageAttachmentId: aid))
                }
            }
        case "turn/start":
            isRunning = true
            let id = "a-\(data["turn"]?.double ?? seq)-stream"
            streamingItemID = id
            items.append(ChatItem(id: id, role: .assistant, text: "", isStreaming: true))
        case "assistant/chunk":
            items = Self.applyChunk(data, items: items, streamingItemID: streamingItemID)
        case "assistant/message":
            let out = Self.applyMessage(data, seq: seq, items: items, streamingItemID: streamingItemID)
            items = out.items
            streamingItemID = out.streamingItemID
        case "tool/call":
            items.append(ChatItem(id: "tool-\(seq)", role: .tool, text: "",
                                  toolName: data["name"]?.string ?? "tool",
                                  toolArgs: data["arguments"]?.string ?? ""))
        case "tool/result":
            let cards = Self.resultCard(view: view, sessionCwd: sessionCwd)
            items.append(ChatItem(id: "toolres-\(seq)", role: .tool,
                                  text: Self.toolResultText(data),
                                  isToolResult: true,
                                  readCard: cards.read,
                                  diffCard: cards.diff))
        case "turn/end":
            isRunning = false
            if let sid = streamingItemID, let idx = items.firstIndex(where: { $0.id == sid }) {
                items[idx].isStreaming = false
            }
            streamingItemID = nil
        default:
            break
        }
    }

    static func foldHistory(_ value: JSONValue, sessionCwd: String?) -> [ChatItem] {
        let entries = value["events"]?.array ?? []
        var items: [ChatItem] = []
        var streamingID: String?

        for entry in entries {
            let event = entry["event"] ?? .null
            let view = entry["view"]
            let type = event["type"]?.string
            let data = event["data"] ?? .null
            let seq = event["seq"]?.double ?? 0
            switch type {
            case "user/message":
                if data["source"]?["kind"]?.string == "user" {
                    let text = textBlocks(data["content"] ?? .null)
                    if !text.isEmpty {
                        items.append(ChatItem(id: "u-\(seq)", role: .user, text: text, messageId: data["id"]?.string))
                    }
                    for aid in imageAttachmentIds(data["content"] ?? .null) {
                        items.append(ChatItem(id: "img-\(seq)-\(aid)", role: .user, text: "", imageAttachmentId: aid))
                    }
                }
            case "turn/start":
                if let sid = streamingID, let idx = items.firstIndex(where: { $0.id == sid }) {
                    items[idx].isStreaming = false
                }
                let id = "a-\(data["turn"]?.double ?? seq)-stream"
                streamingID = id
                items.append(ChatItem(id: id, role: .assistant, text: "", isStreaming: true))
            case "assistant/chunk":
                items = applyChunk(data, items: items, streamingItemID: streamingID)
            case "assistant/message":
                let out = applyMessage(data, seq: seq, items: items, streamingItemID: streamingID)
                items = out.items
                streamingID = out.streamingItemID
            case "tool/call":
                items.append(ChatItem(id: "tool-\(seq)", role: .tool, text: "",
                                      toolName: data["name"]?.string ?? "tool",
                                      toolArgs: data["arguments"]?.string ?? ""))
            case "tool/result":
                let cards = resultCard(view: view, sessionCwd: sessionCwd)
                items.append(ChatItem(id: "toolres-\(seq)", role: .tool,
                                      text: toolResultText(data),
                                      isToolResult: true,
                                      readCard: cards.read,
                                      diffCard: cards.diff))
            case "turn/end":
                if let sid = streamingID, let idx = items.firstIndex(where: { $0.id == sid }) {
                    items[idx].isStreaming = false
                }
                streamingID = nil
            default:
                break
            }
        }
        if let sid = streamingID, let idx = items.firstIndex(where: { $0.id == sid }) {
            items[idx].isStreaming = false
        }
        return items
    }

    // MARK: content-block helpers

    static func textBlocks(_ content: JSONValue) -> String {
        guard let blocks = content.array else { return "" }
        return blocks.compactMap { b in b["type"]?.string == "text" ? b["text"]?.string : nil }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func imageAttachmentIds(_ content: JSONValue) -> [String] {
        guard let blocks = content.array else { return [] }
        return blocks.compactMap { b in
            b["type"]?.string == "image" ? b["attachment"]?["attachmentId"]?.string : nil
        }
    }

    static func reasoningBlocks(_ content: JSONValue) -> String {
        guard let blocks = content.array else { return "" }
        return blocks.compactMap { b in b["type"]?.string == "reasoning" ? b["text"]?.string : nil }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func toolItems(_ content: JSONValue) -> [(name: String?, text: String, isResult: Bool)] {
        guard let blocks = content.array else { return [] }
        return blocks.compactMap { b in
            switch b["type"]?.string {
            case "tool-call":
                return (name: b["name"]?.string ?? "tool", text: b["arguments"]?.string ?? "", isResult: false)
            case "tool-result":
                let t = textBlocks(b["content"] ?? .null)
                let err = b["error"]?["message"]?.string ?? b["error"]?["name"]?.string
                return (name: b["name"]?.string, text: err.map { t.isEmpty ? $0 : t + "\n" + $0 } ?? t, isResult: true)
            default:
                return nil
            }
        }
    }

    static func toolResultText(_ data: JSONValue) -> String {
        let text = textBlocks(data["message"]?["content"] ?? .null)
        let err = data["error"]?["message"]?.string ?? data["error"]?["name"]?.string
        return err.map { text.isEmpty ? $0 : text + "\n" + $0 } ?? text
    }

    static func resultCard(view: JSONValue?, sessionCwd: String?) -> (read: ReadCard?, diff: DiffCard?) {
        guard let view, view["for"]?.string == "result" else { return (nil, nil) }
        let card = view["view"] ?? .null
        return (ReadCard(json: card, sessionCwd: sessionCwd), DiffCard(json: card))
    }

    private static func applyChunk(_ data: JSONValue, items: [ChatItem], streamingItemID: String?) -> [ChatItem] {
        guard let sid = streamingItemID, let idx = items.firstIndex(where: { $0.id == sid }) else { return items }
        var result = items
        let kind = data["chunk"]?["type"]?.string
        let chunkText = data["chunk"]?["text"]?.string ?? ""
        guard !chunkText.isEmpty else { return result }
        if kind == "text-delta" {
            result[idx].text += chunkText
        } else if kind == "reasoning-delta" {
            result[idx].reasoning = (result[idx].reasoning ?? "") + chunkText
        }
        return result
    }

    private static func applyMessage(_ data: JSONValue, seq: Double, items: [ChatItem], streamingItemID: String?) -> (items: [ChatItem], streamingItemID: String?) {
        let message = data["message"] ?? .null
        let content = message["content"] ?? .null
        let text = textBlocks(content)
        let reasoning = reasoningBlocks(content)
        let tools = toolItems(content)
        let messageId = message["id"]?.string
        var result = items
        var sid = streamingItemID

        if let current = sid, let idx = result.firstIndex(where: { $0.id == current }) {
            result[idx].text = text
            result[idx].reasoning = reasoning.isEmpty ? nil : reasoning
            result[idx].isStreaming = false
            result[idx].messageId = messageId
            sid = nil
        } else if !text.isEmpty || !reasoning.isEmpty {
            result.append(ChatItem(id: "a-\(seq)", role: .assistant, text: text, reasoning: reasoning.isEmpty ? nil : reasoning, messageId: messageId))
        }

        for (i, tool) in tools.enumerated() {
            result.append(ChatItem(id: "tool-\(seq)-\(i)", role: .tool,
                                   text: tool.isResult ? tool.text : "",
                                   toolName: tool.name,
                                   toolArgs: tool.isResult ? nil : tool.text,
                                   isToolResult: tool.isResult))
        }
        return (result, sid)
    }
}
