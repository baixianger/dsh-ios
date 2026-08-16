import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SessionListView()
            .tint(Color.dsAccentBlue)
    }
}
