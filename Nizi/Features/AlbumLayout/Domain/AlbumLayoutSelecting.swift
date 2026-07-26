//
//  AlbumLayoutSelecting.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Picks a layout for a page — deterministic, never random. See
/// docs/ALBUM_LAYOUT_SYSTEM.md § Default layout selection. `alternativeLayouts` is for a future
/// "change this page's template" UI; not wired to anything yet this sprint.
protocol AlbumLayoutSelecting {
    func defaultLayout(photoCount: Int, format: AlbumPageFormat) throws -> AlbumPageLayout

    func alternativeLayouts(
        photoCount: Int,
        format: AlbumPageFormat,
        excluding currentLayoutId: String?
    ) throws -> [AlbumPageLayout]
}

/// Fixed, hand-picked default per photo count (§ 19) — not "the first layout returned by the
/// repository," so the default stays stable even if the JSON library's ordering changes.
struct DefaultAlbumLayoutSelector: AlbumLayoutSelecting {
    private let repository: AlbumLayoutRepository

    private static let defaultLayoutIds: [Int: String] = [
        1: "square.1.inset",
        2: "square.2.vertical-split",
        3: "square.3.hero-top",
        4: "square.4.grid"
    ]

    init(repository: AlbumLayoutRepository) {
        self.repository = repository
    }

    func defaultLayout(photoCount: Int, format: AlbumPageFormat) throws -> AlbumPageLayout {
        if let defaultId = Self.defaultLayoutIds[photoCount] {
            let layout = try repository.layout(id: defaultId)
            if layout.supportedFormats.contains(format) {
                return layout
            }
        }
        // Fall back to the first matching layout if there's no hand-picked default for this
        // photo count/format pair (e.g. a photoCount without a curated default yet).
        let candidates = try repository.layouts(photoCount: photoCount, format: format)
        guard let fallback = candidates.first else {
            throw AlbumLayoutError.layoutNotFound("photoCount=\(photoCount) format=\(format.rawValue)")
        }
        return fallback
    }

    func alternativeLayouts(
        photoCount: Int,
        format: AlbumPageFormat,
        excluding currentLayoutId: String?
    ) throws -> [AlbumPageLayout] {
        try repository.layouts(photoCount: photoCount, format: format)
            .filter { $0.id != currentLayoutId }
    }
}
