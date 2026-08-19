import SwiftUI
import UIKit
import PhotosUI

struct SlashCommand: Identifiable {
    let name: String
    let description: String
    let insertion: String
    var id: String { name }
}

struct ComposerView: View {
    private let composerCornerRadius: CGFloat = 22
    @Binding var draft: String
    let isRunning: Bool
    let modelLabel: String
    let permissionLabel: String
    var commands: [SessionCommand] = []
    var modelPickerEnabled = true
    var submissionEnabled = true
    let onOpenModelPicker: () -> Void
    let onChangePermission: (String) -> Void
    let onSend: (UIImage?, String) -> Void
    let onStop: () -> Void

    @StateObject private var speech = SpeechInput()
    @State private var pickedItem: PhotosPickerItem?
    @State private var attachedImage: UIImage?

    private var commandSuggestions: [SlashCommand] {
        guard draft.hasPrefix("/"), !draft.contains(" ") else { return [] }
        return commands
            .filter { draft == "/" || ("/" + $0.name).hasPrefix(draft) }
            .map { SlashCommand(name: "/" + $0.name, description: [$0.description, $0.inputHint].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), insertion: $0.insertion) }
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
                                draft = cmd.insertion
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

            VStack(alignment: .leading, spacing: 8) {
                TextField("继续提问", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .font(.body)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)

                HStack(spacing: 4) {
                    PhotosPicker(selection: $pickedItem, matching: .images) {
                        Image(systemName: "plus")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("添加图片")

                    Menu {
                        ForEach(["read-only", "workspace-write", "danger-full-access"], id: \.self) { opt in
                            Button(permissionName(opt)) { onChangePermission(opt) }
                        }
                    } label: {
                        Image(permissionAssetName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .font(.body)
                            .foregroundStyle(permissionColor)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .accessibilityLabel("权限")
                    .accessibilityValue(permissionLabel)

                    Spacer(minLength: 4)

                    Button(action: onOpenModelPicker) {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.caption)
                            Text(modelLabel)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(!modelPickerEnabled)
                    .accessibilityLabel("模型")
                    .accessibilityValue(modelLabel)

                    Button {
                        speech.toggle { text in
                            if !text.isEmpty { draft += (draft.isEmpty ? "" : " ") + text }
                        }
                    } label: {
                        Image(systemName: speech.isRecording ? "mic.fill" : "mic")
                            .font(.title3)
                            .foregroundStyle(speech.isRecording ? Color.red : Color.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(speech.isRecording ? "停止语音输入" : "语音输入")

                    primaryAction
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: composerCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: composerCornerRadius, style: .continuous)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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

    @ViewBuilder
    private var primaryAction: some View {
        if isRunning {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.primary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("停止生成")
        } else {
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                .foregroundStyle(canSubmit ? Color(uiColor: .systemBackground) : .secondary)
                .frame(width: 44, height: 44)
                .background(canSubmit ? Color.primary : Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel("发送")
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedImage != nil
    }

    private var canSubmit: Bool {
        submissionEnabled && canSend
    }

    private var permissionAssetName: String {
        if permissionLabel == permissionName("danger-full-access") {
            return "DSHAccessFull"
        }
        if permissionLabel == permissionName("workspace-write") {
            return "DSHAccessWorkspaceWrite"
        }
        return "DSHAccessReadOnly"
    }

    private var permissionColor: Color {
        permissionLabel == permissionName("danger-full-access") ? .orange : .primary
    }
}
