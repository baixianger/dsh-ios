import SwiftUI

struct DSHBrandTitle: View {
    var body: some View {
        HStack(spacing: 6) {
            Image("DSHFish")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 20)

            Text("deepseek")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .tracking(-0.8)

            Text("HARNESS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .padding(.horizontal, 5)
                .frame(height: 17)
                .background(Color.primary, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .foregroundStyle(.primary)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("DeepSeek Harness")
    }
}

struct DSHHeroMark: View {
    var body: some View {
        VStack(spacing: 10) {
            Image("DSHFish")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 62, height: 48)
                .accessibilityHidden(true)
            Text("Into the Unknown")
                .font(.system(size: 31, weight: .semibold))
                .tracking(-0.6)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }
}
