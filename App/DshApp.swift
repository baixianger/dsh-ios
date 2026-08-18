import SwiftUI

@main
struct DshApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("dsh.appearance") private var appearance = "system"
    @State private var handoffError: String?

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(preferredColorScheme)
                .onOpenURL(perform: handleOpenURL)
                .alert("配对失败", isPresented: Binding(
                    get: { handoffError != nil },
                    set: { if !$0 { handoffError = nil } }
                )) {
                    Button("好", role: .cancel) { handoffError = nil }
                } message: {
                    Text(handoffError ?? "未知错误")
                }
        }
    }

    private func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "dsh" else { return }
        Task {
            do {
                try await model.pairNetworkServer(scannedURL: url)
            } catch {
                handoffError = error.localizedDescription
            }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
