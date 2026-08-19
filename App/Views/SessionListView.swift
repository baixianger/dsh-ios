import SwiftUI

struct SessionListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var drawerDragOffset: CGFloat = 0

    private let drawerWidth: CGFloat = 320
    private let drawerEdgeActivationWidth: CGFloat = 24
    private var spring: Animation { .spring(response: 0.42, dampingFraction: 0.9) }

    private var expandedCornerRadius: CGFloat {
        horizontalSizeClass == .regular && verticalSizeClass == .regular ? 28 : 44
    }

    private var mainCornerRadius: CGFloat {
        expandedCornerRadius * drawerProgress
    }

    private var drawerProgress: CGFloat {
        let restingProgress: CGFloat = model.showSidebar ? 1 : 0
        let dragProgress = drawerDragOffset / drawerWidth
        return min(max(restingProgress + dragProgress, 0), 1)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            ZStack {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: expandedCornerRadius,
                    topTrailingRadius: expandedCornerRadius,
                    style: .continuous
                )
                .fill(Color(uiColor: .systemBackground))
                .ignoresSafeArea(.container, edges: .vertical)

                SidebarView(
                    onSelectConversation: { id in
                        model.selectConversation(id)
                        closeSidebar()
                    },
                    onClose: { closeSidebar() }
                )
            }
            .frame(width: drawerWidth)
            .frame(maxHeight: .infinity)
            // 所有设备都由固定底层侧栏和可移动上层主体组成。
            .offset(x: 0)
            .opacity(1)
            .allowsHitTesting(model.showSidebar)
            .zIndex(0)

            mainSurface
                .offset(x: drawerWidth * drawerProgress)
                .zIndex(1)
        }
        .simultaneousGesture(drawerGesture)
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .sheet(isPresented: $model.showNewChatDestination) {
            NewChatDestinationView(onDestinationSelected: closeSidebar)
        }
        .alert("操作失败", isPresented: Binding(
            get: { model.operationError != nil },
            set: { if !$0 { model.operationError = nil } }
        )) {
            Button("好", role: .cancel) { model.operationError = nil }
        } message: {
            Text(model.operationError ?? "未知错误")
        }
        .task {
            await model.boot()
        }
    }

    private var mainSurface: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: mainCornerRadius,
                style: .continuous
            )
            .fill(Color(uiColor: .systemBackground))
            .compositingGroup()
            .shadow(
                color: .black.opacity(0.2 * drawerProgress),
                radius: 24,
                x: -10,
                y: 0
            )
            .ignoresSafeArea([.container, .keyboard], edges: .vertical)

            Group {
                if let step = model.storeScreenshotOnboardingStep {
                    ServerOnboardingView(initialStep: step)
                } else if model.servers.isEmpty {
                    ServerOnboardingView()
                } else {
                    NavigationStack {
                        Group {
                            if model.mainPresentation == .blank {
                                Color(uiColor: .systemBackground)
                            } else if model.mainPresentation == .welcome {
                                WelcomeView()
                            } else if model.isStoreScreenshotDemoSession {
                                StoreDemoSessionView()
                            } else if let cid = model.selectedConversationId {
                                SessionDetailView(model: model.sessionModel(for: cid))
                            } else if model.selectedWorkspaceId != nil {
                                BlankChatView()
                            } else {
                                Color(uiColor: .systemBackground)
                            }
                        }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    withAnimation(spring) {
                                        drawerDragOffset = 0
                                        model.showSidebar.toggle()
                                    }
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .accessibilityLabel("切换侧边栏")
                                .accessibilityIdentifier("sidebar.toggle")
                            }
                        }
                    }
                }
            }
            .compositingGroup()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: mainCornerRadius,
                    style: .continuous
                )
            )
        }
    }

    private func closeSidebar() {
        withAnimation(spring) {
            drawerDragOffset = 0
            model.showSidebar = false
        }
    }

    private var drawerGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                if model.showSidebar {
                    drawerDragOffset = max(-drawerWidth, min(0, value.translation.width))
                } else if value.startLocation.x <= drawerEdgeActivationWidth {
                    drawerDragOffset = min(drawerWidth, max(0, value.translation.width))
                }
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    withAnimation(spring) { drawerDragOffset = 0 }
                    return
                }

                let projectedTranslation = value.predictedEndTranslation.width
                let shouldOpen: Bool
                if model.showSidebar {
                    let closingDistance = min(value.translation.width, projectedTranslation)
                    shouldOpen = closingDistance > -drawerWidth * 0.35
                } else if value.startLocation.x <= drawerEdgeActivationWidth {
                    let openingDistance = max(value.translation.width, projectedTranslation)
                    shouldOpen = openingDistance >= drawerWidth * 0.35
                } else {
                    shouldOpen = model.showSidebar
                }

                withAnimation(spring) {
                    model.showSidebar = shouldOpen
                    drawerDragOffset = 0
                }
            }
    }
}

private struct StoreDemoSessionView: View {
    @State private var draft = ""
    private let isChinese = Locale.current.language.languageCode?.identifier == "zh"

    private var userMessage: ChatItem { ChatItem(id: "store-demo-user", role: .user, text: isChinese ? "检查工作区变更，并准备一份简洁的发布摘要。" : "Review the workspace changes and prepare a concise release summary.") }
    private var assistantMessage: ChatItem { ChatItem(id: "store-demo-assistant", role: .assistant, text: isChinese ? "我已检查工作区，并准备好发布摘要。\n\n- 商店素材已整理，等待审核\n- 配置流程已可验证\n- 隐私说明已准备最终核对" : "I reviewed the workspace and prepared the release summary.\n\n- Store assets are organized for review\n- Setup flow is ready to verify\n- Privacy copy is ready for final review") }
    private var activity: [ChatItem] { [
        ChatItem(id: "store-demo-read", role: .tool, text: "", toolName: isChinese ? "读取文件" : "read_file", toolArgs: isChinese ? "商店素材清单" : "Store asset manifest"),
        ChatItem(id: "store-demo-search", role: .tool, text: "", toolName: isChinese ? "搜索文件" : "search_files", toolArgs: isChinese ? "发布说明" : "release notes"),
        ChatItem(id: "store-demo-edit", role: .tool, text: "", toolName: isChinese ? "编辑文件" : "edit_file", toolArgs: isChinese ? "发布摘要" : "Release summary")
    ] }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    MessageBubble(item: userMessage)
                    ActivityGroupCard(
                        reasoning: "I’ll inspect the workspace state, summarize the visible changes, and keep the release notes concise.",
                        tools: activity
                    )
                    MessageBubble(item: assistantMessage)
                }
                .padding()
            }

            ComposerView(
                draft: $draft,
                isRunning: false,
                modelLabel: "DeepSeek · Standard",
                permissionLabel: permissionName("read-only"),
                modelPickerEnabled: false,
                submissionEnabled: false,
                onOpenModelPicker: {},
                onChangePermission: { _ in },
                onSend: { _, _ in },
                onStop: {}
            )
        }
        .navigationTitle(isChinese ? "准备 iOS 发布" : "Prepare the iOS release")
        .navigationBarTitleDisplayMode(.inline)
    }
}
