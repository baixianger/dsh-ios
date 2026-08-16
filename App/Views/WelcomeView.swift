import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("你好")
                        .font(.system(size: 30, weight: .semibold))
                    Text("继续你在 DeepSeek Harness 中的工作")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                Button {
                    Task { await model.newChat() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.pencil")
                        Text("开始新对话").font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.dsAccentBlue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                if !model.workspaces.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("最近项目").font(.headline)
                        ForEach(model.workspaces) { ws in
                            Button {
                                model.selectProject(ws.workspaceId)
                            } label: {
                                projectCard(ws)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("还没有项目", systemImage: "folder")
                    } description: {
                        Text("在 DSH 中创建工作区后，这里会显示你的项目。")
                    }
                }
            }
            .padding(24)
        }
        .background(Color(.systemBackground))
    }

    private func projectCard(_ ws: Workspace) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(ws.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let lastId = model.lastConversationByProject[ws.workspaceId],
                   let c = model.sessions.first(where: { $0.sessionId == lastId }) {
                    Text(c.title ?? "无标题")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color.dsSurfacePrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct BlankChatView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("这个项目还没有对话").font(.headline)
            Text("开始第一条对话，它会自动归属到当前项目").font(.subheadline).foregroundStyle(.secondary)
            Button {
                Task { await model.newChat() }
            } label: {
                Label("新建聊天", systemImage: "square.and.pencil")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color.dsAccentBlue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
