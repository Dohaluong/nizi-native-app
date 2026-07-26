//
//  AlbumPhotoLoadState.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// See docs/specs/SPEC-REAL-ALBUM.md § 7.3. `degraded` is the fast preview `PHImageManager`
/// hands back immediately (`PHImageResultIsDegradedKey == true`); `success` is the final,
/// request-quality image. `degraded` is never treated as an error — it's exactly the
/// "photo appears fast, then sharpens" behavior Apple Photos itself has.
enum AlbumPhotoLoadState: Sendable {
    case idle
    case loading
    case degraded(PlatformImage)
    case success(PlatformImage)
    case missing
    case failure(AlbumPhotoProviderError)
}
