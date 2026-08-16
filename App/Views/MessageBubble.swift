import SwiftUI
import UIKit

struct MessageBubble: View {
    let item: ChatItem
    var feedback: MessageFeedbackItem? = nil
    var onRemoveMessage: ((String) -> Void)? = nil
    var onEditMessage: ((String, String) -> Void)? = nil
    var onSteerMessage: ((String) -> Void)? = nil
    var onToggleFeedback: ((String) -> Void)? = nil
    var onEditFeedbackNote: ((String) -> Void)? = nil

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
        .contextMenu {
            if !item.text.isEmpty {
                Button {
                    UIPasteboard.general.string = item.text
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
            }
            if let mid = item.messageId {
                if let onEditMessage {
                    Button {
                        onEditMessage(mid, item.text)
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                }
                if let onSteerMessage {
                    Button {
                        onSteerMessage(mid)
                    } label: {
                        Label("重新生成", systemImage: "arrow.clockwise")
                    }
                }
                if let onRemoveMessage {
                    Button(role: .destructive) {
                        onRemoveMessage(mid)
                    } label: {
                        Label("删除消息", systemImage: "trash")
                    }
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
                    if item.messageId != nil, let onToggleFeedback {
                        Button {
                            onToggleFeedback("positive")
                        } label: {
                            Label(feedback?.rating == "positive" ? "已赞" : "赞", systemImage: feedback?.rating == "positive" ? "hand.thumbsup.fill" : "hand.thumbsup")
                        }
                        Button {
                            onToggleFeedback("negative")
                        } label: {
                            Label(feedback?.rating == "negative" ? "已踩" : "踩", systemImage: feedback?.rating == "negative" ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        }
                        if let fb = feedback, !fb.rating.isEmpty, let onEditFeedbackNote {
                            Button {
                                onEditFeedbackNote(fb.messageId)
                            } label: {
                                Label(fb.note == nil ? "补充说明" : "备注", systemImage: fb.note == nil ? "text.bubble" : "text.bubble.fill")
                            }
                        }
                    }
                    SpeakButton(text: item.text)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)

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
}

struct SpeakButton: View {
    let text: String
    @StateObject private var reader = SpeechReader()

    var body: some View {
        Button {
            reader.toggle(text)
        } label: {
            Label(reader.isSpeaking ? "停止" : "朗读", systemImage: reader.isSpeaking ? "stop.circle" : "speaker.wave.2")
        }
    }
}

struct ReasoningDisclosure: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            MarkdownText(text: text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .padding(.top, 6)
        } label: {
            Label("思考过程", systemImage: "brain")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
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
                    Image(systemName: item.isToolResult ? "arrow.turn.down.left" : "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.isToolResult ? (item.toolName ?? "结果") : (item.toolName ?? "tool"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

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
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
    }
}

struct ToolCallGroupCard: View {
    let items: [ChatItem]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver").font(.caption).foregroundStyle(.secondary)
                    Text("工具调用").font(.subheadline.weight(.semibold))
                    Text("· \(items.count)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(10)

            if expanded {
                Divider()
                ForEach(items) { item in
                    ToolCallCard(item: item)
                }
                .padding(8)
            }
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
    }
}
