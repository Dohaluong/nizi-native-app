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
/// renders `kind.placeholderText` until a real Album's user types actual content into it (see
/// `AlbumTextAssignment`/`AlbumTextBlockEditSheet`).
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
    /// § user request — "còn cần chọn màu chữ": hex string (e.g. `"#FFFFFF"`), same shape
    /// `AlbumLayoutBackground.value` already uses. Defaults to `"#000000"` for any text block
    /// encoded before this field existed (see `init(from:)`) — every layout shipped so far has no
    /// `textColor` key at all, and black matches what an unstyled `Text` already rendered as.
    let textColor: String
    /// § user request — "cho phép chọn kiểu: Title/Sub-title/Paragraph. Dùng để trang trí văn bản
    /// sau này": semantic only, exactly like `AlbumLayoutSlot.role` — the renderer doesn't read
    /// this to alter anything yet (no automatic font/size/weight preset applied per kind). It's
    /// Layout-Studio-authored metadata, prepared now for a future decorative-styling feature to
    /// key off of, the same "planning-time metadata, future features can read it without the
    /// renderer needing to know" posture `AlbumLayoutSlotRole` already documents.
    let kind: AlbumTextBlockKind

    init(
        id: String, order: Int, frame: AlbumLayoutFrame,
        horizontalAlignment: AlbumTextHorizontalAlignment, verticalAlignment: AlbumTextVerticalAlignment,
        fontFamily: AlbumTextFontFamily, fontSize: Double, fontStyle: AlbumTextFontStyle,
        textColor: String = "#000000", kind: AlbumTextBlockKind = .paragraph
    ) {
        self.id = id
        self.order = order
        self.frame = frame
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontStyle = fontStyle
        self.textColor = textColor
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case id, order, frame, horizontalAlignment, verticalAlignment, fontFamily, fontSize, fontStyle, textColor, kind
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
    ///
    /// § lesson learned from that same bug — decoding `fontStyle` straight as `AlbumTextFontStyle`
    /// via `decodeIfPresent` is *not* enough on its own: `decodeIfPresent` only skips a *missing*
    /// key gracefully — a key that's *present* but holds a raw value this enum no longer
    /// recognizes (e.g. `"boldItalic"`, valid while that case briefly existed) still throws
    /// `dataCorrupted`, which would fail the whole `AlbumLayoutLibrary` decode exactly the same way
    /// the missing-`fontStyle` bug did. Decoding the raw `String` first and switching over it by
    /// hand means an unrecognized value degrades to `.regular` instead of taking every Album page
    /// down with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        order = try container.decode(Int.self, forKey: .order)
        frame = try container.decode(AlbumLayoutFrame.self, forKey: .frame)
        horizontalAlignment = try container.decode(AlbumTextHorizontalAlignment.self, forKey: .horizontalAlignment)
        verticalAlignment = try container.decode(AlbumTextVerticalAlignment.self, forKey: .verticalAlignment)
        fontFamily = try container.decode(AlbumTextFontFamily.self, forKey: .fontFamily)
        fontSize = try container.decode(Double.self, forKey: .fontSize)
        if let rawStyle = try container.decodeIfPresent(String.self, forKey: .fontStyle) {
            fontStyle = AlbumTextFontStyle(legacyRawValue: rawStyle)
        } else if let legacyWeight = try container.decodeIfPresent(String.self, forKey: .legacyFontWeight) {
            fontStyle = legacyWeight == "bold" ? .bold : .regular
        } else {
            fontStyle = .regular
        }
        textColor = try container.decodeIfPresent(String.self, forKey: .textColor) ?? "#000000"
        kind = try container.decodeIfPresent(AlbumTextBlockKind.self, forKey: .kind) ?? .paragraph
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
        try container.encode(textColor, forKey: .textColor)
        try container.encode(kind, forKey: .kind)
    }
}

/// § user request — "Phần text trong Layout studio cho phép chọn kiểu: Title/Sub-title/Paragraph.
/// Dùng để trang trí văn bản sau này": mirrors `AlbumLayoutSlotRole`'s exact shape and posture —
/// Studio-authored. Its one effect on the renderer so far is `placeholderText` below (§ user
/// request — "sẽ có placeholder tương ứng"); it doesn't drive any automatic font/size/weight
/// preset yet.
enum AlbumTextBlockKind: String, Codable, Hashable, CaseIterable {
    case title
    case subtitle
    case paragraph

    /// § user request — "Toại title sẽ là: Title, loại subtitle sẽ là Sub title, loại paragraph
    /// sẽ là Lorem ipsum...": shown in place of real content while a text block is still empty
    /// (`AlbumTextBlockView.displayText`) — deliberately fixed, unlocalized sample copy (the same
    /// convention "Lorem ipsum" itself already follows), not routed through `localizedString`.
    var placeholderText: String {
        switch self {
        case .title: return "Title"
        case .subtitle: return "Sub title"
        case .paragraph: return "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
        }
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
/// Italic-Bold" — later refined to "Regular, Italic, Bold, Underline" (§ user report: the
/// Bold-Italic icon didn't reliably render, and 4 simple, single-attribute options with correct
/// icons matter more than every permutation). `.regular`/`.italic`/`.bold` are font-*face* choices
/// (resolved against the family's own named faces in Presentation); `.underline` is not a face at
/// all — it's a text decoration applied on top of the regular face (see `AlbumTextBlockView`'s own
/// `.underline(_:)` modifier).
enum AlbumTextFontStyle: String, Codable, Hashable, CaseIterable {
    case regular
    case italic
    case bold
    case underline

    /// § lesson learned from the "mất hết ảnh" bug — a plain `init?(rawValue:)` (the synthesized
    /// one) returns `nil` for any string this enum doesn't currently recognize, which upstream
    /// (`AlbumTextBlock`/`AlbumTextAssignment`'s own custom `init(from decoder:)`) would otherwise
    /// have to `decodeIfPresent` the enum directly and let a *present-but-unrecognized* raw value
    /// throw `dataCorrupted` — exactly the failure mode that took every Album page down before.
    /// This degrades any unrecognized value (including `"boldItalic"`, valid while that case
    /// briefly existed before being replaced with `.underline`) to `.regular` instead.
    init(legacyRawValue: String) {
        self = AlbumTextFontStyle(rawValue: legacyRawValue) ?? .regular
    }
}
