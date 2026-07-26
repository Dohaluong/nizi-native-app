//
//  AlbumLayoutBackground.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Only `solid` this sprint — see docs/ALBUM_LAYOUT_SYSTEM.md § JSON schema. The type is kept
/// separate from `AlbumLayoutBackground.value` so a future background kind (e.g. gradient) is an
/// additive enum case, not a breaking model change.
enum AlbumLayoutBackgroundType: String, Codable, Hashable {
    case solid
}

/// `value` is a hex color string (e.g. `"#FFFFFF"`) when `type == .solid`.
struct AlbumLayoutBackground: Codable, Hashable {
    let type: AlbumLayoutBackgroundType
    let value: String
}
