//
//  PhotoRendering.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreGraphics
import Foundation

/// The only interface Photo Editor's Application/Presentation layers use to turn a photo + recipe
/// into pixels — supersedes Bước 2's simpler `PhotoEditorImageLoading` now that there's an actual
/// Core Image pipeline behind it (PHOTO-EDITOR.md § 14.1, § 20.2). Two entry points, never one,
/// per § 15: preview is deliberately cheaper and bounded; full resolution is only ever requested
/// for export/share/save-a-copy/photobook, never for live editing.
protocol PhotoRendering: Sendable {
    /// A preview-quality render — bounded well below device/asset resolution, safe to call on
    /// every preset pick or slider drag. `targetSize` is a pixel size, not points (callers already
    /// account for screen scale where relevant, matching the convention `PhotoAssetProvider` and
    /// `AlbumPhotoProviding` already use).
    func renderPreview(photoId: String, recipe: PhotoEditRecipe, targetSize: CGSize) async throws -> CGImage

    /// Renders at the source's full resolution — only for export/share/save/photobook (§ 15.2).
    /// Never called on a slider-drag cadence.
    func renderFullResolution(photoId: String, recipe: PhotoEditRecipe) async throws -> CGImage
}

enum PhotoRenderError: Error, Equatable {
    case assetUnavailable
    case sourceUnavailable
    case decodeFailed
    case renderFailed
}
