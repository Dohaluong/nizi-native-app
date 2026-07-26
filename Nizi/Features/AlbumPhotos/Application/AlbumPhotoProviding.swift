//
//  AlbumPhotoProviding.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Loads pixels for an `AlbumPhotoReference` — the one abstraction standing between
/// `AlbumPhotoView` and `PHImageManager`. `ApplePhotosAlbumPhotoProvider` (Infrastructure) is the
/// production implementation; `MockAlbumPhotoProvider` (Presentation) is used by SwiftUI Previews
/// and tests, which must never require Photos Library access (docs/specs/SPEC-REAL-ALBUM.md
/// § 7.4, § 35).
///
/// `AsyncStream` (rather than a single `async throws -> UIImage`) is what lets a caller observe
/// `.degraded` followed by `.success` for the same request — `PHImageManager` itself delivers
/// results this way (multiple callbacks per request), and collapsing that into a single return
/// value would throw away the "fast preview, then sharpen" behavior § 7.3 asks for.
protocol AlbumPhotoProviding: Sendable {
    func loadImage(request: AlbumPhotoRequest) -> AsyncStream<AlbumPhotoLoadState>
    func cancelRequest(for requestId: UUID) async
}
