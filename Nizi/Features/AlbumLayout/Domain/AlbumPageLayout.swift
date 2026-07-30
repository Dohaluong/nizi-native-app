//
//  AlbumPageLayout.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// A layout template: canvas, slots, and how they're filled — never a specific photo ID.
/// See docs/ALBUM_LAYOUT_SYSTEM.md § Layout template vs. page content.
///
/// `id` is a persistent identifier (`{format}.{photoCount}.{variant}`, e.g.
/// `"square.3.hero-top"`) — once an Album page references it, it must never change or be
/// reused for a different layout.
struct AlbumPageLayout: Identifiable, Codable, Hashable {
    let id: String
    /// English development name (debug/log/fallback use) — not shown to users directly.
    let name: String
    /// Localization key for the user-facing layout name (e.g. `"album.layout.square.3.hero_top"`).
    /// See docs/ALBUM_LAYOUT_SYSTEM.md § Localization.
    let nameKey: String
    let photoCount: Int
    let supportedFormats: [AlbumPageFormat]
    let referenceCanvas: AlbumReferenceCanvas
    let background: AlbumLayoutBackground
    let slots: [AlbumLayoutSlot]
    /// § user request — "Thêm chữ" — decorative text blocks, never counted toward `photoCount`/
    /// `slots.count` (see `AlbumTextBlock`'s own doc comment). Decoded with a default of `[]`
    /// (`decodeIfPresent`, not `decode`) so every `album-layouts.json` entry authored before this
    /// feature existed still decodes unchanged — same backward-compatible-migration posture
    /// `AlbumPhotoAssignment.crop` already uses for the same reason.
    let textBlocks: [AlbumTextBlock]

    init(
        id: String, name: String, nameKey: String, photoCount: Int,
        supportedFormats: [AlbumPageFormat], referenceCanvas: AlbumReferenceCanvas,
        background: AlbumLayoutBackground, slots: [AlbumLayoutSlot], textBlocks: [AlbumTextBlock] = []
    ) {
        self.id = id
        self.name = name
        self.nameKey = nameKey
        self.photoCount = photoCount
        self.supportedFormats = supportedFormats
        self.referenceCanvas = referenceCanvas
        self.background = background
        self.slots = slots
        self.textBlocks = textBlocks
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, nameKey, photoCount, supportedFormats, referenceCanvas, background, slots, textBlocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        nameKey = try container.decode(String.self, forKey: .nameKey)
        photoCount = try container.decode(Int.self, forKey: .photoCount)
        supportedFormats = try container.decode([AlbumPageFormat].self, forKey: .supportedFormats)
        referenceCanvas = try container.decode(AlbumReferenceCanvas.self, forKey: .referenceCanvas)
        background = try container.decode(AlbumLayoutBackground.self, forKey: .background)
        slots = try container.decode([AlbumLayoutSlot].self, forKey: .slots)
        textBlocks = try container.decodeIfPresent([AlbumTextBlock].self, forKey: .textBlocks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(nameKey, forKey: .nameKey)
        try container.encode(photoCount, forKey: .photoCount)
        try container.encode(supportedFormats, forKey: .supportedFormats)
        try container.encode(referenceCanvas, forKey: .referenceCanvas)
        try container.encode(background, forKey: .background)
        try container.encode(slots, forKey: .slots)
        try container.encode(textBlocks, forKey: .textBlocks)
    }
}

struct AlbumLayoutLibrary: Codable {
    let schemaVersion: Int
    let layouts: [AlbumPageLayout]
}
