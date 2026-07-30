//
//  AlbumTextAssignment.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// § user request — real, per-Page content for one of the layout's `AlbumTextBlock`s: both the
/// user-typed `text` (or none yet, in which case the renderer shows the block's own placeholder —
/// see `AlbumTextBlockView`) and the actual style used to display it on *this* Page. The same
/// "layout template describes the default, the Page holds what's actually used" split
/// `AlbumLayoutSlot`/`AlbumPhotoAssignment` already uses for photos — `AlbumTextBlock`'s own
/// style fields are only ever the *starting point* a fresh assignment is seeded with (see
/// `AlbumEditActionApplying.freshTextAssignments`); § user request — "cho phép chọn cỡ chữ, font,
/// weight, căn lề ... trong modal editor" — a real Album's own text-edit screen then lets the user
/// change these per-Page, independently of the Layout Studio's own design-time defaults.
struct AlbumTextAssignment: Identifiable, Codable, Hashable {
    let id: String
    let textBlockId: String
    var text: String
    var horizontalAlignment: AlbumTextHorizontalAlignment
    var verticalAlignment: AlbumTextVerticalAlignment
    var fontFamily: AlbumTextFontFamily
    var fontSize: Double
    var fontWeight: AlbumTextFontWeight

    init(
        id: String, textBlockId: String, text: String,
        horizontalAlignment: AlbumTextHorizontalAlignment = .center,
        verticalAlignment: AlbumTextVerticalAlignment = .center,
        fontFamily: AlbumTextFontFamily = .system,
        fontSize: Double = 32,
        fontWeight: AlbumTextFontWeight = .regular
    ) {
        self.id = id
        self.textBlockId = textBlockId
        self.text = text
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontWeight = fontWeight
    }

    private enum CodingKeys: String, CodingKey {
        case id, textBlockId, text, horizontalAlignment, verticalAlignment, fontFamily, fontSize, fontWeight
    }

    /// § backward compatibility — an assignment encoded before the style fields existed (this
    /// session's very first cut, text-only) still decodes: falls back to the same static defaults
    /// the memberwise `init` above uses, since the *original* layout block that seeded it isn't
    /// reachable from here (only the target's own `Decoder` is).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        textBlockId = try container.decode(String.self, forKey: .textBlockId)
        text = try container.decode(String.self, forKey: .text)
        horizontalAlignment = try container.decodeIfPresent(AlbumTextHorizontalAlignment.self, forKey: .horizontalAlignment) ?? .center
        verticalAlignment = try container.decodeIfPresent(AlbumTextVerticalAlignment.self, forKey: .verticalAlignment) ?? .center
        fontFamily = try container.decodeIfPresent(AlbumTextFontFamily.self, forKey: .fontFamily) ?? .system
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 32
        fontWeight = try container.decodeIfPresent(AlbumTextFontWeight.self, forKey: .fontWeight) ?? .regular
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(textBlockId, forKey: .textBlockId)
        try container.encode(text, forKey: .text)
        try container.encode(horizontalAlignment, forKey: .horizontalAlignment)
        try container.encode(verticalAlignment, forKey: .verticalAlignment)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(fontWeight, forKey: .fontWeight)
    }
}
