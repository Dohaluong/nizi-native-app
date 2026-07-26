//
//  PhotoAssetExporter.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreGraphics
import ImageIO
import Photos
import UniformTypeIdentifiers

/// Production `PhotoAssetExporting` — the first (and only) place this app writes to the Photos
/// library rather than just reading from it. Everything else in Photo Editor is deliberately
/// non-destructive (`PhotoEditRepository` only ever persists a recipe); this exists specifically
/// for the Album/Event "save as a real photo, not just a recipe" flow, where the caller needs an
/// actual new `PHAsset` to swap an Album page's/Event's selection onto.
final class PhotoAssetExporter: PhotoAssetExporting {
    private let imageManager: PHImageManager

    init(imageManager: PHImageManager = PHImageManager.default()) {
        self.imageManager = imageManager
    }

    func exportEditedCopy(photoId: String, recipe: PhotoEditRecipe, renderer: PhotoRendering, deleteOriginal: Bool) async throws -> String {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw PhotoAssetExportError.libraryPermissionDenied
        }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [photoId], options: nil).firstObject else {
            throw PhotoAssetExportError.assetUnavailable
        }

        let originalData = try await requestOriginalData(for: asset)
        guard let metadata = Self.correctedMetadata(from: originalData) else {
            throw PhotoAssetExportError.metadataUnavailable
        }

        let renderedImage = try await renderer.renderFullResolution(photoId: photoId, recipe: recipe)
        let jpegData = try Self.encodeJPEG(renderedImage, metadata: metadata)

        let newLocalIdentifier = try await Self.createAsset(from: jpegData, matching: asset)

        if deleteOriginal {
            try await Self.deleteAsset(asset)
        }

        return newLocalIdentifier
    }

    private func requestOriginalData(for asset: PHAsset) async throws -> Data {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.version = .current

        return try await withCheckedThrowingContinuation { continuation in
            imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if info?[PHImageErrorKey] != nil {
                    continuation.resume(throwing: PhotoAssetExportError.assetUnavailable)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: PhotoAssetExportError.assetUnavailable)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    /// The original asset's full EXIF/GPS/TIFF metadata, with any orientation tag forced to
    /// "normal" — `renderFullResolution`'s output pixels are already upright (§ 10's "orientation
    /// normalized once, immediately after decode"), so re-attaching the *original* file's rotation
    /// instruction on top would tell every EXIF-aware viewer to rotate an already-upright image a
    /// second time.
    private static func correctedMetadata(from originalData: Data) -> CFDictionary? {
        guard let source = CGImageSourceCreateWithData(originalData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        var corrected = properties
        corrected[kCGImagePropertyOrientation] = 1
        if var tiff = corrected[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            corrected[kCGImagePropertyTIFFDictionary] = tiff
        }
        return corrected as CFDictionary
    }

    private static func encodeJPEG(_ image: CGImage, metadata: CFDictionary) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoAssetExportError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, metadata)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoAssetExportError.encodingFailed
        }
        return data as Data
    }

    /// `creationDate`/`location` are set to match the original — not covered by the JPEG's own
    /// EXIF (Photos reads its library-level date/location from the asset record, not just the
    /// file's metadata) — so the new asset sorts and maps right next to the original in Photos
    /// instead of appearing "taken now."
    private static func createAsset(from jpegData: Data, matching originalAsset: PHAsset) async throws -> String {
        var newLocalIdentifier: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetCreationRequest.forAsset()
                let resourceOptions = PHAssetResourceCreationOptions()
                resourceOptions.uniformTypeIdentifier = UTType.jpeg.identifier
                creationRequest.addResource(with: .photo, data: jpegData, options: resourceOptions)
                creationRequest.creationDate = originalAsset.creationDate
                creationRequest.location = originalAsset.location
                newLocalIdentifier = creationRequest.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            throw PhotoAssetExportError.libraryWriteFailed
        }
        guard let newLocalIdentifier else {
            throw PhotoAssetExportError.libraryWriteFailed
        }
        return newLocalIdentifier
    }

    private static func deleteAsset(_ asset: PHAsset) async throws {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            }
        } catch {
            throw PhotoAssetExportError.libraryWriteFailed
        }
    }
}
