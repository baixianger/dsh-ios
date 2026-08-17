import SwiftUI

@main
struct DshApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("dsh.appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(preferredColorScheme)
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
