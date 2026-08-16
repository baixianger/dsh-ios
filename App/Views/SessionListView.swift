import SwiftUI

struct SessionListView: View {
    @EnvironmentObject private var model: AppModel

    private let drawerWidth: CGFloat = 320

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
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                model.showSidebar = true
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(Color.dsSurfaceElevated, in: Circle())
                                .overlay(Circle().stroke(Color.dsHairline.opacity(0.7), lineWidth: 0.5))
                        }
                        .accessibilityLabel("打开侧边栏")
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
            }
            .offset(x: model.showSidebar ? drawerWidth : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.showSidebar)

            if model.showSidebar {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            model.showSidebar = false
                        }
                    }
                    .transition(.opacity)
            }

            SidebarView { id in
                model.selectConversation(id)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    model.showSidebar = false
                }
            }
            .frame(width: drawerWidth)
            .frame(maxHeight: .infinity)
            .background(Color.dsBackground)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.dsHairline.opacity(0.5)).frame(width: 0.5)
            }
            .offset(x: model.showSidebar ? 0 : -drawerWidth)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.showSidebar)
        }
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .task {
            await model.boot()
        }
    }
}
