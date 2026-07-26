//
//  PhotoRenderEngine.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreImage
import Photos

/// Production `PhotoRendering` — the only place in Photo Editor that touches `CIContext`,
/// `CIImage`, or `PHImageManager` directly. One instance is meant to live for the whole editing
/// session (constructed once by `PhotoEditorViewModel`), never recreated per render call, so its
/// `CIContext` is genuinely reused (PHOTO-EDITOR.md § 18.3) instead of paying Metal/GPU setup cost
/// on every preset pick or slider drag.
///
/// Deliberately never introduces `UIImage`/`PlatformImage` anywhere in this pipeline — preview
/// pixels come in as a `CGImage` straight from `PHImageManager` and go out as a `CGImage` straight
/// from `CIContext.createCGImage`; full-resolution pixels come in as raw `Data` (never decoded
/// through `UIImage`) and go out the same way. This is what § 18.3's "không chuyển đổi liên tục
/// giữa `UIImage` và `CIImage`" actually means in code, not just an aspiration.
final class PhotoRenderEngine: PhotoRendering, @unchecked Sendable {
    private let imageManager: PHCachingImageManager
    private let ciContext: CIContext
    private let presetRepository: PresetRepository
    private let presetRenderer: PresetRendering

    init(
        imageManager: PHCachingImageManager = PHCachingImageManager(),
        ciContext: CIContext? = nil,
        presetRepository: PresetRepository = BundlePresetRepository(),
        presetRenderer: PresetRendering = PresetRenderer()
    ) {
        self.imageManager = imageManager
        // GPU-backed (Metal) by default — `ciContext` is only ever overridden in tests, where no
        // GPU is guaranteed to be available.
        self.ciContext = ciContext ?? CIContext(options: [.useSoftwareRenderer: false])
        self.presetRepository = presetRepository
        self.presetRenderer = presetRenderer
    }

    func renderPreview(photoId: String, recipe: PhotoEditRecipe, targetSize: CGSize) async throws -> CGImage {
        let sourceImage = try await requestBoundedImage(photoId: photoId, targetSize: targetSize)
        let ciImage = CIImage(cgImage: sourceImage)
        let processed = applyRecipe(recipe, to: ciImage)
        return try render(processed)
    }

    func renderFullResolution(photoId: String, recipe: PhotoEditRecipe) async throws -> CGImage {
        let (data, orientation) = try await requestOriginalDataAndOrientation(photoId: photoId)
        guard let sourceImage = CIImage(data: data) else {
            throw PhotoRenderError.decodeFailed
        }
        // The one required orientation-normalization step (§ 10, Bước 3): raw asset data has no
        // baked-in rotation, only a separate orientation tag — applying it here, once, immediately
        // after decode, is what keeps every later filter stage working in "already upright" space.
        let oriented = sourceImage.oriented(orientation)
        let processed = applyRecipe(recipe, to: oriented)
        return try render(processed)
    }

    // MARK: - Pipeline

    /// Bước 4 (Preset) — resolves `recipe.presetId` to its `PresetDefinition` and hands off to
    /// `PresetRenderer`. Still a structural passthrough for everything else the pipeline diagram
    /// (PHOTO-EDITOR.md § 10) calls for — Auto Enhance and manual Adjust are Bước 5/6, added here
    /// the same way, without touching `renderPreview`/`renderFullResolution` or the PHAsset-
    /// loading/orientation code above.
    private func applyRecipe(_ recipe: PhotoEditRecipe, to image: CIImage) -> CIImage {
        guard let presetId = recipe.presetId,
              recipe.presetIntensity > 0,
              let preset = presetRepository.preset(id: presetId)
        else {
            return image
        }
        return presetRenderer.applyPreset(preset, intensity: recipe.presetIntensity, to: image)
    }

    private func render(_ image: CIImage) throws -> CGImage {
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            throw PhotoRenderError.renderFailed
        }
        return cgImage
    }

    // MARK: - PHAsset access

    private func requestBoundedImage(photoId: String, targetSize: CGSize) async throws -> CGImage {
        let asset = try fetchAsset(photoId: photoId)

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.version = .current // § 17.5 — edit what the user already sees in Photos.

        let manager = imageManager
        let requestBox = PhotoRenderRequestBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestId = manager.requestImage(
                    for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options
                ) { image, info in
                    if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    if info?[PHImageErrorKey] as? Error != nil {
                        NiziLogger.photoEditor.error("photo_editor_render_preview_request_error photoId=\(photoId, privacy: .private)")
                        continuation.resume(throwing: PhotoRenderError.sourceUnavailable)
                        return
                    }
                    guard let cgImage = image?.cgImage else {
                        continuation.resume(throwing: PhotoRenderError.sourceUnavailable)
                        return
                    }
                    continuation.resume(returning: cgImage)
                }
                requestBox.set(requestId)
            }
        } onCancel: {
            requestBox.cancel(using: manager)
        }
    }

    private func requestOriginalDataAndOrientation(photoId: String) async throws -> (Data, CGImagePropertyOrientation) {
        let asset = try fetchAsset(photoId: photoId)

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.version = .current

        let manager = imageManager
        let requestBox = PhotoRenderRequestBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestId = manager.requestImageDataAndOrientation(
                    for: asset, options: options
                ) { data, _, orientation, info in
                    if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    if info?[PHImageErrorKey] as? Error != nil {
                        NiziLogger.photoEditor.error("photo_editor_render_fullres_request_error photoId=\(photoId, privacy: .private)")
                        continuation.resume(throwing: PhotoRenderError.sourceUnavailable)
                        return
                    }
                    guard let data else {
                        continuation.resume(throwing: PhotoRenderError.sourceUnavailable)
                        return
                    }
                    continuation.resume(returning: (data, orientation))
                }
                requestBox.set(requestId)
            }
        } onCancel: {
            requestBox.cancel(using: manager)
        }
    }

    private func fetchAsset(photoId: String) throws -> PHAsset {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [photoId], options: nil).firstObject else {
            NiziLogger.photoEditor.error("photo_editor_render_asset_fetch_failed photoId=\(photoId, privacy: .private)")
            throw PhotoRenderError.assetUnavailable
        }
        return asset
    }
}

/// Same cancellation-handoff shape used elsewhere in this app (`PhotoKitAssetProvider`'s own
/// `ImageRequestBox`) — lets `onCancel` reach a request id that's only known synchronously inside
/// the completion closure.
private final class PhotoRenderRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var requestId: PHImageRequestID?

    func set(_ id: PHImageRequestID) {
        lock.lock()
        requestId = id
        lock.unlock()
    }

    func cancel(using manager: PHImageManager) {
        lock.lock()
        let id = requestId
        lock.unlock()
        if let id {
            manager.cancelImageRequest(id)
        }
    }
}
