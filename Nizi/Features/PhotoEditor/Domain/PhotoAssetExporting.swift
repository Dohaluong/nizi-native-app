//
//  PhotoAssetExporting.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreGraphics
import Foundation

/// Writes a fully-rendered edit as a brand-new photo into the user's Photos library — the one
/// place in Photo Editor that turns a non-destructive `PhotoEditRecipe` into real pixels the
/// Photos app (and this app's own Album/Event data) can reference by a new identifier. Used only
/// when saving from an Album or Event context; a standalone edit has nothing to swap a reference
/// in, so it stays on the plain recipe-only save path.
protocol PhotoAssetExporting: Sendable {
    /// Renders `recipe` at full resolution against `photoId`, preserves that photo's own
    /// EXIF/GPS/TIFF metadata (with the orientation tag corrected to "already upright," since the
    /// rendered pixels are — re-applying the original tag on top would double-rotate the result),
    /// and writes it as a new asset dated/located to match the original (so it sorts right next to
    /// it in Photos). If `deleteOriginal` is `true`, the original asset is deleted afterward.
    /// Returns the new asset's `PHAsset.localIdentifier`.
    func exportEditedCopy(photoId: String, recipe: PhotoEditRecipe, renderer: PhotoRendering, deleteOriginal: Bool) async throws -> String
}

enum PhotoAssetExportError: Error, Equatable {
    case libraryPermissionDenied
    case assetUnavailable
    case metadataUnavailable
    case encodingFailed
    case libraryWriteFailed
}
