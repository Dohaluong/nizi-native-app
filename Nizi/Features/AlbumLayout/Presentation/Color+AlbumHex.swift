//
//  Color+AlbumHex.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/30/26.
//

import SwiftUI
import UIKit

/// Shared by every `AlbumLayout` renderer that stores a color as a plain hex string
/// (`AlbumLayoutBackground.value`, `AlbumTextBlock.textColor`/`AlbumTextAssignment.textColor`) —
/// one parser so all three can never silently disagree on what a given hex string looks like.
extension Color {
    /// Minimal `"#RRGGBB"` parser (§ Background) — the only color shape any of these fields use.
    init?(albumHex hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.removeAll { $0 == "#" }
        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }

    /// § user request — "còn cần chọn màu chữ": the inverse of `init?(albumHex:)`, so a
    /// `ColorPicker`'s own `Color` selection round-trips back into the same `"#RRGGBB"` string
    /// shape the model stores (`AlbumTextBlockEditSheet`'s only use so far).
    var albumHexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
