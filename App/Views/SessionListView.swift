import SwiftUI

struct SessionListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let drawerWidth: CGFloat = 320
    private var isCompact: Bool { sizeClass == .compact }
    private var spring: Animation { .spring(response: 0.35, dampingFraction: 0.85) }

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                Group {
                    if let cid = model.selectedConversationId {
                        SessionDetailView(model: model.sessionModel(for: cid))
                    } else if model.selectedWorkspaceId != nil {
                        BlankChatView()
                    } else {
                        WelcomeView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(spring) { model.showSidebar.toggle() }
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(Color.dsSurfaceElevated, in: Circle())
                                .overlay(Circle().stroke(Color.dsHairline.opacity(0.7), lineWidth: 0.5))
                        }
                        .accessibilityLabel("切换侧边栏")
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
            }
            // iPhone: 主界面右移让出侧边栏；iPad: 主界面不动，保持可操作。
            .offset(x: isCompact && model.showSidebar ? drawerWidth : 0)
            .animation(spring, value: model.showSidebar)

            // iPhone 用遮罩关闭；iPad 无遮罩，主界面可继续操作。
            if isCompact && model.showSidebar {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { closeSidebar() }
                    .transition(.opacity)
            }

            SidebarView(
                onSelectConversation: { id in
                    model.selectConversation(id)
                    closeSidebar()
                },
                onClose: { closeSidebar() }
            )
            .frame(width: drawerWidth)
            .frame(maxHeight: .infinity)
            .background(Color.dsBackground)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.dsHairline.opacity(0.5)).frame(width: 0.5)
            }
            .offset(x: model.showSidebar ? 0 : -drawerWidth)
            .animation(spring, value: model.showSidebar)
        }
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .task {
            await model.boot()
        }
    }

    private func closeSidebar() {
        withAnimation(spring) { model.showSidebar = false }
    }
}
