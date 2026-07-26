//
//  AlbumPhotoCrop.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// How a photo is cropped within its slot — prepared now, not fully editable yet (§ 5.4). Every
/// assignment this sprint uses `.centered`; a crop editor is future work.
struct AlbumPhotoCrop: Codable, Hashable, Sendable {
    /// -1...1
    var normalizedOffsetX: Double
    /// -1...1
    var normalizedOffsetY: Double
    /// >= 1
    var scale: Double

    static let centered = AlbumPhotoCrop(normalizedOffsetX: 0, normalizedOffsetY: 0, scale: 1)
}
