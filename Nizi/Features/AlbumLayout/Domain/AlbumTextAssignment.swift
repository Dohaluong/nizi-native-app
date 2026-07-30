//
//  AlbumTextAssignment.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// § user request — real, per-Page user-typed content for one of the layout's `AlbumTextBlock`s.
/// The same "layout template describes geometry/style, the Page holds the actual content" split
/// `AlbumLayoutSlot`/`AlbumPhotoAssignment` already uses for photos: `AlbumTextBlock` never
/// changes once authored in the Layout Studio, but each real Album page using that layout has its
/// own independent `text` (or none yet, in which case the renderer shows the block's own
/// placeholder — see `AlbumTextBlockView`).
struct AlbumTextAssignment: Identifiable, Codable, Hashable {
    let id: String
    let textBlockId: String
    var text: String
}
