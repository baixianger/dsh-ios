import SwiftUI
import UIKit
import Foundation

struct MessageBubble: View {
    let item: ChatItem
    var feedback: MessageFeedbackItem? = nil
    var onToggleFeedback: ((String) -> Void)? = nil
    var onEditFeedbackNote: ((String) -> Void)? = nil
    var onBranch: (() -> Void)? = nil

    var body: some View {
        Group {
            if item.imageAttachmentId != nil {
                imageBubble
            } else {
                switch item.role {
            case .user:
                userBubble
            case .assistant:
                assistantBlock
            case .tool:
                ToolCallCard(item: item)
            case .notice:
                Text(item.text).font(.caption).foregroundStyle(.secondary)
            }
            }
        }
    }

    private var imageBubble: some View {
        HStack {
            if item.role == .user { Spacer(minLength: 48) }
            if let data = item.imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.dsSurfacePrimary)
                    .frame(width: 180, height: 140)
                    .overlay { ProgressView() }
            }
            if item.role != .user { Spacer(minLength: 48) }
        }
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack {
                Spacer(minLength: 48)
                Text(item.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.dsSurfacePrimary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: 300, alignment: .trailing)
            }
            messageActionsMenu(includesCopy: true)
        }
    }

    private var assistantBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reasoning = item.reasoning, !reasoning.isEmpty {
                ReasoningDisclosure(text: reasoning)
            }
            if item.text.isEmpty {
                if item.isStreaming {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("正在生成…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if item.isStreaming {
                // Streaming deltas mutate this item every few ms — render cheap plain text
                // and only run the Markdown block parser once the turn finalizes.
                Text(item.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MarkdownText(text: item.text)
            }

            if !item.isStreaming && !item.text.isEmpty {
                HStack(spacing: 18) {
                    Button {
                        UIPasteboard.general.string = item.text
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .labelStyle(.iconOnly)
                    if item.messageId != nil, let onToggleFeedback {
                        Button {
                            onToggleFeedback("positive")
                        } label: {
                            Label(feedback?.rating == "positive" ? "已赞" : "赞", systemImage: feedback?.rating == "positive" ? "hand.thumbsup.fill" : "hand.thumbsup")
                        }
                        .labelStyle(.iconOnly)
                        Button {
                            onToggleFeedback("negative")
                        } label: {
                            Label(feedback?.rating == "negative" ? "已踩" : "踩", systemImage: feedback?.rating == "negative" ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        }
                        .labelStyle(.iconOnly)
                        if let fb = feedback, !fb.rating.isEmpty, let onEditFeedbackNote {
                            Button {
                                onEditFeedbackNote(fb.messageId)
                            } label: {
                                Label(fb.note == nil ? "补充说明" : "备注", systemImage: fb.note == nil ? "text.bubble" : "text.bubble.fill")
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                    if let onBranch {
                        Button(action: onBranch) {
                            Label {
                                Text("在新对话中分支")
                            } icon: {
                                Image("DSHBranch")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                            }
                        }
                        .labelStyle(.iconOnly)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)

                if let note = feedback?.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func messageActionsMenu(includesCopy: Bool) -> some View {
        if includesCopy && !item.text.isEmpty {
            Menu {
                Button("复制", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = item.text
                }
            } label: {
                Label("更多消息操作", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
    }
}

struct ReasoningDisclosure: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { expanded.toggle() }
            } label: {
                compactDisclosureLabel(title: String(localized: "思考过程"), systemImage: "brain", expanded: expanded)
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "已展开" : "已折叠")

            if expanded {
                MarkdownText(text: text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
                    .padding(.bottom, 8)
            }
        }
    }
}

struct ToolCallCard: View {
    let item: ChatItem
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: activityIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(activityTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(activityTitle)
            .accessibilityValue(expanded ? "已展开" : "已折叠")

            if expanded {
                if let read = item.readCard {
                    ReadCardView(card: read)
                } else if let diff = item.diffCard {
                    DiffCardView(card: diff)
                } else {
                    let body = item.isToolResult ? item.text : (item.toolArgs ?? "")
                    if !body.isEmpty {
                        Text(body)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var activityTitle: String {
        let fallback = item.isToolResult ? "工具结果" : "工具调用"
        guard let name = item.toolName, !name.isEmpty else { return fallback }
        return name
    }

    private var activityIcon: String {
        let name = (item.toolName ?? "").lowercased()
        if item.readCard != nil || name.contains("read") { return "book" }
        if item.diffCard != nil || name.contains("patch") || name.contains("edit") { return "doc.badge.gearshape" }
        if name.contains("plan") { return "list.bullet.clipboard" }
        if name.contains("exec") || name.contains("command") || name.contains("shell") { return "terminal" }
        return item.isToolResult ? "arrow.turn.down.left" : "wrench.and.screwdriver"
    }
}

struct ActivityGroupCard: View {
    let reasoning: String?
    let tools: [ChatItem]
    @State private var expanded = false

    private var rows: [CompactToolActivity] {
        var result: [CompactToolActivity] = []
        for item in tools {
            if item.isToolResult, let index = result.indices.last, result[index].result == nil {
                result[index].result = item
            } else {
                result.append(CompactToolActivity(call: item, result: nil))
            }
        }
        return result
    }

    private var summary: String {
        let calls = rows.map(\.call)
        guard !calls.isEmpty else { return String(localized: "思考过程") }

        var reads = 0
        var searches = 0
        var edits = 0
        var commands = 0
        var others = 0
        for call in calls {
            let name = (call.toolName ?? "").localizedLowercase
            if call.readCard != nil || name.contains("read") || name.contains("view") {
                reads += 1
            } else if name.contains("search") || name.contains("find") || name.contains("grep") {
                searches += 1
            } else if call.diffCard != nil || name.contains("edit") || name.contains("patch") || name.contains("write") {
                edits += 1
            } else if name.contains("exec") || name.contains("shell") || name.contains("command") || name.contains("bash") || name == "run_code" {
                commands += 1
            } else {
                others += 1
            }
        }

        let isChinese = Locale.current.language.languageCode?.identifier.hasPrefix("zh") == true
        var parts: [String] = []
        if isChinese {
            if edits > 0 { parts.append("编辑 \(edits) 个文件") }
            if reads > 0 { parts.append("读取 \(reads) 个文件") }
            if searches > 0 { parts.append("搜索 \(searches) 次") }
            if commands > 0 { parts.append("运行 \(commands) 条命令") }
            if others > 0 { parts.append("调用 \(others) 个工具") }
        } else {
            if edits > 0 { parts.append("Edited \(edits) file\(edits == 1 ? "" : "s")") }
            if reads > 0 { parts.append("read \(reads) file\(reads == 1 ? "" : "s")") }
            if searches > 0 { parts.append("\(searches) search\(searches == 1 ? "" : "es")") }
            if commands > 0 { parts.append("ran \(commands) command\(commands == 1 ? "" : "s")") }
            if others > 0 { parts.append("used \(others) tool\(others == 1 ? "" : "s")") }
        }
        return parts.joined(separator: isChinese ? "，" : ", ")
    }

    private var summaryIcon: String {
        let names = rows.map { ($0.call.toolName ?? "").localizedLowercase }.joined(separator: " ")
        if names.contains("edit") || names.contains("patch") || names.contains("write") { return "pencil" }
        if names.contains("search") || names.contains("find") || names.contains("grep") { return "magnifyingglass" }
        if names.contains("read") || names.contains("view") { return "book" }
        if reasoning != nil && rows.isEmpty { return "brain" }
        return "terminal"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: summaryIcon)
                        .font(.subheadline)
                        .frame(width: 18)
                    Text(summary)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .foregroundStyle(.secondary)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summary)
            .accessibilityValue(expanded ? "已展开" : "已折叠")

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    if let reasoning, !reasoning.isEmpty {
                        CompactReasoningRow(text: reasoning)
                    }

                    ForEach(rows) { row in
                        CompactToolActivityRow(activity: row)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct CompactToolActivity: Identifiable {
    let id: String
    let call: ChatItem
    var result: ChatItem?

    init(call: ChatItem, result: ChatItem?) {
        self.id = call.id
        self.call = call
        self.result = result
    }
}

private struct CompactReasoningRow: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { expanded.toggle() }
            } label: {
                compactDisclosureLabel(title: String(localized: "思考过程"), systemImage: "brain", expanded: expanded)
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "已展开" : "已折叠")

            if expanded {
                MarkdownText(text: text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
                    .padding(.bottom, 8)
            }
        }
    }
}

private struct CompactToolActivityRow: View {
    let activity: CompactToolActivity
    @State private var expanded = false

    private var detailText: String {
        let resultText = activity.result?.text ?? ""
        if !resultText.isEmpty { return resultText }
        return activity.call.toolArgs ?? activity.call.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { expanded.toggle() }
            } label: {
                compactDisclosureLabel(title: title, systemImage: icon, expanded: expanded)
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "已展开" : "已折叠")

            if expanded {
                if let read = activity.result?.readCard ?? activity.call.readCard {
                    ReadCardView(card: read).padding(.leading, 24).padding(.bottom, 8)
                } else if let diff = activity.result?.diffCard ?? activity.call.diffCard {
                    DiffCardView(card: diff).padding(.leading, 24).padding(.bottom, 8)
                } else if !detailText.isEmpty {
                    Text(detailText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 24)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private var title: String {
        let name = activity.call.toolName ?? (activity.call.isToolResult ? "工具结果" : "工具调用")
        if let description = decodedArgument("description"), !description.isEmpty {
            let prefix = commandLike ? String(localized: "运行") : name
            return "\(prefix)  \(description)"
        }
        let arguments = (activity.call.toolArgs ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !arguments.isEmpty else { return name }
        return "\(name)  \(arguments)"
    }

    private var commandLike: Bool {
        let name = (activity.call.toolName ?? "").localizedLowercase
        return name == "run_code" || name.contains("exec") || name.contains("shell") || name.contains("command") || name.contains("bash")
    }

    private func decodedArgument(_ key: String) -> String? {
        guard let arguments = activity.call.toolArgs,
              let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object[key] as? String
    }

    private var icon: String {
        let name = (activity.call.toolName ?? "").localizedLowercase
        if activity.result?.readCard != nil || activity.call.readCard != nil || name.contains("read") { return "book" }
        if activity.result?.diffCard != nil || activity.call.diffCard != nil || name.contains("edit") || name.contains("patch") { return "pencil" }
        if name.contains("search") || name.contains("find") || name.contains("grep") { return "magnifyingglass" }
        if commandLike { return "terminal" }
        return "wrench.and.screwdriver"
    }
}

@ViewBuilder
private func compactDisclosureLabel(
    title: String,
    systemImage: String,
    expanded: Bool
) -> some View {
    HStack(spacing: 6) {
        Image(systemName: systemImage)
            .frame(width: 18)
        Text(title)
            .lineLimit(1)
        Spacer(minLength: 4)
        Image(systemName: "chevron.right")
            .font(.caption2)
            .rotationEffect(.degrees(expanded ? 90 : 0))
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
    .frame(height: 30)
    .contentShape(Rectangle())
}
