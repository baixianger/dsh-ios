import SwiftUI
import UIKit
import PhotosUI

struct SlashCommand: Identifiable {
    let name: String
    let description: String
    var id: String { name }
}

extension SlashCommand {
    static let known: [SlashCommand] = [
        SlashCommand(name: "/compact", description: "压缩历史"),
        SlashCommand(name: "/plan on", description: "进入计划模式"),
        SlashCommand(name: "/plan off", description: "退出计划模式"),
        SlashCommand(name: "/goal ", description: "设置目标"),
        SlashCommand(name: "/title ", description: "重命名会话"),
        SlashCommand(name: "/fork", description: "分支会话"),
        SlashCommand(name: "/cwd ", description: "切换目录"),
    ]
}

struct ComposerView: View {
    @Binding var draft: String
    let isRunning: Bool
    let modelLabel: String
    let permissionLabel: String
    let onOpenModelPicker: () -> Void
    let onChangePermission: (String) -> Void
    let onSend: (UIImage?, String) -> Void
    let onStop: () -> Void

    @StateObject private var speech = SpeechInput()
    @State private var pickedItem: PhotosPickerItem?
    @State private var attachedImage: UIImage?

    private var commandSuggestions: [SlashCommand] {
        guard draft.hasPrefix("/"), !draft.contains(" ") else { return [] }
        if draft == "/" { return SlashCommand.known }
        return SlashCommand.known.filter { $0.name.hasPrefix(draft) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if speech.isRecording {
                HStack(spacing: 8) {
                    Image(systemName: "waveform").foregroundStyle(.red)
                    Text(speech.liveText.isEmpty ? "正在聆听…" : speech.liveText)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !commandSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(commandSuggestions) { cmd in
                            Button {
                                draft = cmd.name
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(cmd.name).font(.caption.monospaced().weight(.medium))
                                    Text(cmd.description).font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.dsSurfacePrimary, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .transition(.opacity)
            }

            if let attachedImage {
                HStack {
                    Image(uiImage: attachedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("已附加图片").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { self.attachedImage = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 6)
            }

            HStack(spacing: 8) {
                Button(action: onOpenModelPicker) {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu").font(.caption2)
                        Text(modelLabel).font(.caption).lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(["read-only", "workspace-write", "danger-full-access"], id: \.self) { opt in
                        Button(permissionName(opt)) { onChangePermission(opt) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "lock").font(.caption2)
                        Text(permissionLabel).font(.caption).lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 2)

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Image(systemName: "plus")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 6)
                .accessibilityLabel("添加图片")

                Button {
                    speech.toggle { text in
                        if !text.isEmpty { draft += (draft.isEmpty ? "" : " ") + text }
                    }
                } label: {
                    Image(systemName: speech.isRecording ? "mic.fill" : "mic")
                        .font(.title3)
                        .foregroundStyle(speech.isRecording ? Color.red : Color.primary)
                }
                .padding(.bottom, 6)
                .accessibilityLabel(speech.isRecording ? "停止语音输入" : "语音输入")

                TextField("消息", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if isRunning {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill").font(.title2).foregroundStyle(.red)
                    }
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedImage == nil)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .animation(.easeInOut(duration: 0.15), value: speech.isRecording)
        .onChange(of: pickedItem) { _, item in
            Task {
                guard let item else { return }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    attachedImage = ui
                }
                pickedItem = nil
            }
        }
    }

    private func send() {
        let text = draft
        let image = attachedImage
        draft = ""
        attachedImage = nil
        onSend(image, text)
    }
}
