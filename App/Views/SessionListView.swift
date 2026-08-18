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
                if model.servers.isEmpty {
                    ServerOnboardingView()
                } else {
                    NavigationStack {
                        Group {
                            if model.mainPresentation == .blank {
                                Color(uiColor: .systemBackground)
                            } else if model.mainPresentation == .welcome {
                                WelcomeView()
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
