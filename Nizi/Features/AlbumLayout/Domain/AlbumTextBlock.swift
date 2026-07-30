//
//  AlbumTextBlock.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// § user request — "Cần thêm tính năng Thêm chữ. 1 Khối chữ tương đương như 1 Frame": a text
/// block is a layout-template element with its own position/size (`frame`, the same
/// `AlbumLayoutFrame` unit every photo slot already uses), independent of `AlbumLayoutSlot`
/// (never counted toward `photoCount`/`AlbumLayoutValidator`'s slot-count check — see its own doc
/// comment). Only the layout *template* is described here (geometry + style); there is no
/// per-Album, user-authored text content yet (§ prepared now, not fully editable — same posture
/// `AlbumPhotoCrop`'s own doc comment already takes for a different field) — every text block
/// currently always renders its own localized placeholder ("album.textBlock.placeholder" —
/// "Viết ở đây"/"Write here"), never real user-typed text.
struct AlbumTextBlock: Identifiable, Codable, Hashable {
    let id: String
    /// Must be unique within its own layout (not globally) — mirrors `AlbumLayoutSlot.order`.
    let order: Int
    let frame: AlbumLayoutFrame
    let horizontalAlignment: AlbumTextHorizontalAlignment
    let verticalAlignment: AlbumTextVerticalAlignment
    let fontFamily: AlbumTextFontFamily
    let fontSize: Double
    let fontWeight: AlbumTextFontWeight
}

/// "Có các kiểu căn lề trái phải giữa" — left/center/right, mapped to a `TextAlignment` (how
/// multi-line text aligns within its own box) in Presentation.
enum AlbumTextHorizontalAlignment: String, Codable, Hashable, CaseIterable {
    case left
    case center
    case right
}

/// "Căn trên dưới giữa" — top/center/bottom, mapped to where the whole text box sits within its
/// `frame` (not the same thing as `AlbumTextHorizontalAlignment`, which only affects text *within*
/// its own box) in Presentation.
enum AlbumTextVerticalAlignment: String, Codable, Hashable, CaseIterable {
    case top
    case center
    case bottom
}

/// "Chọn font chữ ... Hiện tại cho phép lấy các font theo hệ thống của iOS": a curated subset of
/// iOS's own built-in ("Font Book") family names — not the full list (iOS ships 40+ families,
/// most either script-specific for non-Latin languages or unsuitable display faces for photo
/// captions) — chosen for a mix of clean/readable (system, Helvetica Neue, Avenir(+Next), Georgia,
/// Palatino, Times New Roman, Gill Sans, Optima) and a few decorative options (Didot, Futura,
/// Baskerville, American Typewriter, Noteworthy, Snell Roundhand, Marker Felt, Papyrus) — every
/// raw value is the *exact* family name iOS itself reports via `UIFont.familyNames`, matched at
/// render time in Presentation (never a PostScript/face name — `AlbumTextFontWeight` is what picks
/// the actual face for a given family, since that mapping differs per family and only the OS
/// itself reliably knows it).
enum AlbumTextFontFamily: String, Codable, Hashable, CaseIterable {
    case system = "System"
    case helveticaNeue = "Helvetica Neue"
    case avenir = "Avenir"
    case avenirNext = "Avenir Next"
    case georgia = "Georgia"
    case baskerville = "Baskerville"
    case didot = "Didot"
    case futura = "Futura"
    case gillSans = "Gill Sans"
    case optima = "Optima"
    case palatino = "Palatino"
    case timesNewRoman = "Times New Roman"
    case americanTypewriter = "American Typewriter"
    case noteworthy = "Noteworthy"
    case snellRoundhand = "Snell Roundhand"
    case markerFelt = "Marker Felt"
    case papyrus = "Papyrus"
}

/// "Cỡ chữ, font-weight" — a practical subset (not iOS's full 9-step `UIFont.Weight` range, which
/// is overkill for a captions picker and, for most non-system families below, wouldn't resolve to
/// a different face anyway).
enum AlbumTextFontWeight: String, Codable, Hashable, CaseIterable {
    case regular
    case medium
    case semibold
    case bold
}
