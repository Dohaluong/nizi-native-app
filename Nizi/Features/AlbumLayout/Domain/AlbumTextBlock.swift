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
    let fontStyle: AlbumTextFontStyle

    init(
        id: String, order: Int, frame: AlbumLayoutFrame,
        horizontalAlignment: AlbumTextHorizontalAlignment, verticalAlignment: AlbumTextVerticalAlignment,
        fontFamily: AlbumTextFontFamily, fontSize: Double, fontStyle: AlbumTextFontStyle
    ) {
        self.id = id
        self.order = order
        self.frame = frame
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontStyle = fontStyle
    }

    private enum CodingKeys: String, CodingKey {
        case id, order, frame, horizontalAlignment, verticalAlignment, fontFamily, fontSize, fontStyle
        /// § bug report — "mất hết ảnh": the entire `AlbumLayoutLibrary` decode is one array —
        /// one `AlbumTextBlock` still carrying the *old* field name (from before `fontWeight` was
        /// renamed to `fontStyle`, exported by an out-of-date copy of the Layout Studio) failed
        /// with `keyNotFound(fontStyle)`, which threw all the way up through `layouts[30].
        /// textBlocks[0]` and took every single layout down with it — every Album page's renderer
        /// then found no layout at all (`BundleAlbumLayoutRepository` never partially succeeds)
        /// and rendered nothing, looking exactly like every photo had vanished.
        case legacyFontWeight = "fontWeight"
    }

    /// § same bug report — decodes `fontStyle` if present; falls back to translating whatever
    /// *old* `fontWeight` value is there instead (only `"bold"` has a real equivalent — `medium`/
    /// `semibold`/`regular` all become `.regular`, the closest available style); falls back to
    /// `.regular` if neither key exists at all. This is the one place in the whole "Thêm chữ"
    /// feature that was missed when `fontWeight` became `fontStyle` — every other type involved
    /// (`AlbumPageLayout.textBlocks`, `AlbumTextAssignment`) already had this same defensive
    /// posture; `AlbumTextBlock` itself was still relying on synthesized (all-fields-required)
    /// `Codable`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        order = try container.decode(Int.self, forKey: .order)
        frame = try container.decode(AlbumLayoutFrame.self, forKey: .frame)
        horizontalAlignment = try container.decode(AlbumTextHorizontalAlignment.self, forKey: .horizontalAlignment)
        verticalAlignment = try container.decode(AlbumTextVerticalAlignment.self, forKey: .verticalAlignment)
        fontFamily = try container.decode(AlbumTextFontFamily.self, forKey: .fontFamily)
        fontSize = try container.decode(Double.self, forKey: .fontSize)
        if let style = try container.decodeIfPresent(AlbumTextFontStyle.self, forKey: .fontStyle) {
            fontStyle = style
        } else if let legacyWeight = try container.decodeIfPresent(String.self, forKey: .legacyFontWeight) {
            fontStyle = legacyWeight == "bold" ? .bold : .regular
        } else {
            fontStyle = .regular
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(order, forKey: .order)
        try container.encode(frame, forKey: .frame)
        try container.encode(horizontalAlignment, forKey: .horizontalAlignment)
        try container.encode(verticalAlignment, forKey: .verticalAlignment)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(fontStyle, forKey: .fontStyle)
    }
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
/// render time in Presentation (never a PostScript/face name — `AlbumTextFontStyle` is what picks
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

/// § user request — "font-weight sẽ thay bằng các định dạng cơ bản: Regular, Italic, Bold,
/// Italic-Bold": the 4 basic style permutations most fonts actually ship as distinct named faces
/// (not a thickness scale like the previous `medium`/`semibold` steps — those rarely resolved to a
/// visibly different face for most of the curated families below anyway; italic is a genuinely
/// different, commonly-available axis instead).
enum AlbumTextFontStyle: String, Codable, Hashable, CaseIterable {
    case regular
    case italic
    case bold
    case boldItalic
}
