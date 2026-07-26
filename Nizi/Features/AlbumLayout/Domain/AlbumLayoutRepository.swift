//
//  AlbumLayoutRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Read-only access to the layout template library. `BundleAlbumLayoutRepository`
/// (Infrastructure) is the only implementation this sprint, but Domain only knows this protocol —
/// nothing here says the library comes from the app bundle, so a future server-synced or
/// user-authored source can conform without touching any caller. See
/// docs/ALBUM_LAYOUT_SYSTEM.md § Repository.
protocol AlbumLayoutRepository {
    func loadLibrary() throws -> AlbumLayoutLibrary

    func layout(id: String) throws -> AlbumPageLayout

    func layouts(photoCount: Int, format: AlbumPageFormat) throws -> [AlbumPageLayout]
}
