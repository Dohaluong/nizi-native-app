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

/// Which edge of the slot `AlbumSlotGradientOverlay`'s dark gradient starts from and fades inward
/// toward — see that struct's own doc comment for the full shape.
enum AlbumGradientEdge: String, Codable, Hashable, CaseIterable {
    case top
    case bottom
    case left
    case right
}

/// § user request — "phần ảnh cho phép chọn option gradient đen trong suốt, mục đích làm nền cho
/// chữ": an optional dark gradient painted on top of a slot's photo (inside the same corner-radius
/// clip), so a text block sitting over part of a photo stays legible. `edge` is where the gradient
/// is darkest; it fades to fully transparent over `extentPercent` of that edge's own axis (height
/// for `.top`/`.bottom`, width for `.left`/`.right`) — the remaining `100 - extentPercent` of the
/// slot is left untouched. E.g. `edge: .bottom, extentPercent: 30` means the gradient spans only
/// the bottom 30% of the slot's height, going from black (at `opacity`) at the very bottom edge to
/// fully transparent at the 30%-from-bottom mark. `opacity` is a second, independent knob — the
/// gradient's own maximum alpha at `edge`, before it fades to 0 (§ user request — "Có thêm opacity
/// của gradien nữa").
struct AlbumSlotGradientOverlay: Codable, Hashable {
    let edge: AlbumGradientEdge
    /// 0...100 — how much of the slot's edge-to-edge dimension the gradient's fade spans, starting
    /// at `edge`.
    let extentPercent: Double
    /// 0...1 — the gradient's alpha at `edge` itself, before it fades to 0 over `extentPercent`.
    let opacity: Double
}

struct AlbumLayoutSlot: Identifiable, Codable, Hashable {
    let id: String
    let order: Int
    let role: AlbumLayoutSlotRole
    let preferredOrientation: AlbumSlotOrientation
    let frame: AlbumLayoutFrame
    let contentMode: AlbumSlotContentMode
    let cornerRadius: Double
    /// `nil` (the default — every existing `album-layouts.json` entry authored before this feature
    /// existed has no `gradientOverlay` key at all) means no overlay is painted. A plain Optional
    /// stored property on an otherwise fully-synthesized `Codable` type already decodes/encodes a
    /// missing key as `nil` without needing a custom `init(from:)` — unlike `AlbumTextBlock.
    /// fontStyle`, there's no *legacy, differently-named* key here to fall back to.
    let gradientOverlay: AlbumSlotGradientOverlay?

    init(
        id: String, order: Int, role: AlbumLayoutSlotRole, preferredOrientation: AlbumSlotOrientation,
        frame: AlbumLayoutFrame, contentMode: AlbumSlotContentMode, cornerRadius: Double,
        gradientOverlay: AlbumSlotGradientOverlay? = nil
    ) {
        self.id = id
        self.order = order
        self.role = role
        self.preferredOrientation = preferredOrientation
        self.frame = frame
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
        self.gradientOverlay = gradientOverlay
    }
}
