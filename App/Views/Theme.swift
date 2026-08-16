import SwiftUI
import UIKit

private func rgb(_ hex: UInt32) -> (Double, Double, Double) {
    (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
}

extension Color {
    init(hex: UInt32) {
        let (r, g, b) = rgb(hex)
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    init(light: UInt32, dark: UInt32) {
        let (lr, lg, lb) = rgb(light)
        let (dr, dg, db) = rgb(dark)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: dr, green: dg, blue: db, alpha: 1)
                : UIColor(red: lr, green: lg, blue: lb, alpha: 1)
        })
    }

    // DeepSeek accent palette (works in both modes)
    static let dsAccentBlue = Color(hex: 0x0A84FF)
    static let dsAccentGreen = Color(hex: 0x20C997)
    static let dsWarning = Color(hex: 0xFF9F0A)
    static let dsDestructive = Color(hex: 0xFF453A)

    // Adaptive surfaces (light ≈ systemGray, dark ≈ spec tokens)
    static let dsSurfacePrimary = Color(light: 0xF2F2F7, dark: 0x202022)
    static let dsSurfaceSecondary = Color(light: 0xEDEDF0, dark: 0x1C1C1E)
    static let dsSurfaceElevated = Color(light: 0xFFFFFF, dark: 0x29292B)
    static let dsSurfaceSelected = Color(light: 0xE5E5EA, dark: 0x242426)
    static let dsBackground = Color(light: 0xF7F7F8, dark: 0x000000)
    static let dsHairline = Color(light: 0xD7D7DC, dark: 0x2C2C2E)
}
