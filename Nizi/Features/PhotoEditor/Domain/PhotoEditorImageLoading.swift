//
//  PhotoEditorImageLoading.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreGraphics
import Foundation

/// The only interface Photo Editor's Application/Presentation layers use to get pixels for a
/// photo — mirrors how `PhotoAssetProvider` (Memory Discovery) and `AlbumPhotoProviding` (Album)
/// each stand between their own screens and PhotoKit. Photo Editor gets its own small version of
/// this rather than depending on either of those modules' Infrastructure, per
/// docs/architecture/ARCHITECTURE.md § 2 ("modules don't reach into each other's infrastructure").
///
/// `Sendable` since the production implementation talks to `PHCachingImageManager` from
/// arbitrary `Task`s, same reasoning as `PHAssetResolving`/`AlbumPhotoProviding`.
protocol PhotoEditorImageLoading: Sendable {
    /// A preview-quality image for editing — capped well below full device/asset resolution (see
    /// `PhotoRenderEngine` in Bước 3), never the full original. `PlatformImage` (not `CIImage`) at
    /// this layer since Domain must not import CoreImage or Photos.
    func loadPreview(photoId: String, targetSize: CGSize) async throws -> PlatformImage
}

enum PhotoEditorImageError: Error, Equatable {
    case assetUnavailable
    case loadFailed
}
