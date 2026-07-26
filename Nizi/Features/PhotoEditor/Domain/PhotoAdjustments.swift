//
//  PhotoAdjustments.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// The six Adjust sliders (PHOTO-EDITOR.md § 8) in normalized, engine-facing units — the UI's
/// `-100...+100` display range is a Presentation-layer concern (Bước 5), not stored here. Every
/// value defaults to `0`, matching "Original" — never `nil`, since an unedited photo is expressed
/// as an all-zero `PhotoAdjustments`, not the absence of one.
struct PhotoAdjustments: Codable, Equatable, Sendable {
    var exposure: Float = 0
    var contrast: Float = 0
    var highlights: Float = 0
    var shadows: Float = 0
    var warmth: Float = 0
    var saturation: Float = 0

    static let identity = PhotoAdjustments()

    var isIdentity: Bool { self == .identity }
}
