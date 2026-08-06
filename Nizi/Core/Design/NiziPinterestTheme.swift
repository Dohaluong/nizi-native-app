import SwiftUI

/// The shared product chrome from `NiziUITests/DESIGN-pinterest.md`.
///
/// Photos retain their own colours; these tokens are only for app chrome, navigation, cards,
/// text and controls. Keeping them central prevents each archive screen from drifting into a
/// different interpretation of the light theme.
enum NiziPinterestTheme {
    static let primary = Color(hex: 0xE60023)
    static let primaryPressed = Color(hex: 0xCC001F)
    static let canvas = Color(hex: 0xFFFFFF)
    static let surfaceSoft = Color(hex: 0xFBFBF9)
    static let surfaceCard = Color(hex: 0xF6F6F3)
    static let secondaryBackground = Color(hex: 0xE5E5E0)
    static let hairline = Color(hex: 0xDADAD3)
    static let ink = Color(hex: 0x000000)
    static let body = Color(hex: 0x33332E)
    static let mutedText = Color(hex: 0x62625B)
    static let darkSurface = Color(hex: 0x262622)

    static let cornerRadius: CGFloat = 16
    static let largeCornerRadius: CGFloat = 32
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
