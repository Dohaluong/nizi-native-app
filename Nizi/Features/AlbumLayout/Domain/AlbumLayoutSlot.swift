//
//  AlbumLayoutSlot.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// A slot's position and size, expressed in the layout's `referenceCanvas` units — never actual
/// on-screen points. See docs/ALBUM_LAYOUT_SYSTEM.md § Coordinate system.
struct AlbumLayoutFrame: Codable, Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// Semantic only — never used by the renderer to alter a slot's frame. Exists for layout
/// recommendation/authoring purposes (e.g. "which slot is the hero photo") that later features
/// can read without the renderer needing to know what a "hero" is.
enum AlbumLayoutSlotRole: String, Codable, Hashable {
    case hero
    case supporting
}

/// How a photo fills its slot. The renderer clips to the slot frame regardless — this only
/// controls whether the photo view itself scales-to-fill (cropping) or scales-to-fit (letterbox)
/// within that frame.
enum AlbumSlotContentMode: String, Codable, Hashable {
    case fill
    case fit
}

/// Planning-time metadata only — the renderer never reads this (a slot's actual on-screen shape
/// always comes from `frame`, scaled). `AlbumLayoutPairSelector`/`AlbumPhotoSlotAssigner` (see
/// `Features/AlbumCreation`) use it to score which photo fits which slot best.
/// `.square` is the flexible case: it accepts landscape, portrait, or square photos (see
/// docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 8.1), just scored lower than an exact match.
/// `.any` accepts everything at an even lower (but still positive) score.
enum AlbumSlotOrientation: String, Codable, Hashable {
    case landscape
    case portrait
    case square
    case any
}

struct AlbumLayoutSlot: Identifiable, Codable, Hashable {
    let id: String
    let order: Int
    let role: AlbumLayoutSlotRole
    let preferredOrientation: AlbumSlotOrientation
    let frame: AlbumLayoutFrame
    let contentMode: AlbumSlotContentMode
    let cornerRadius: Double
}
