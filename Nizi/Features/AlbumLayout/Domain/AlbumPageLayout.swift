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
}

struct AlbumLayoutLibrary: Codable {
    let schemaVersion: Int
    let layouts: [AlbumPageLayout]
}
