//
//  PhotoEditorAssetLoader.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Photos

/// Production `PhotoEditorImageLoading` — the only place in Photo Editor allowed to touch
/// `PHAsset`/`PHImageManager` directly. Deliberately its own small implementation rather than a
/// dependency on `PhotoKitAssetProvider` (Memory Discovery) or `ApplePhotosAlbumPhotoProvider`
/// (Album) — see the note on `PhotoEditorImageLoading`.
///
/// Requests `.current` version (not `.original`) — matches `ApplePhotosAlbumPhotoProvider`'s own
/// choice and PHOTO-EDITOR.md § 17.5's recommendation: edit whatever the user already sees in
/// Photos (including any edits made there), not a version they can't see anywhere else in the app.
final class PhotoEditorAssetLoader: PhotoEditorImageLoading, @unchecked Sendable {
    private let imageManager: PHCachingImageManager

    init(imageManager: PHCachingImageManager = PHCachingImageManager()) {
        self.imageManager = imageManager
    }

    func loadPreview(photoId: String, targetSize: CGSize) async throws -> PlatformImage {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [photoId], options: nil).firstObject else {
            NiziLogger.photoEditor.error("photo_editor_asset_fetch_failed photoId=\(photoId, privacy: .private)")
            throw PhotoEditorImageError.assetUnavailable
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.version = .current

        let manager = imageManager
        let requestBox = PhotoEditorImageRequestBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestId = manager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    if info?[PHImageErrorKey] as? Error != nil {
                        NiziLogger.photoEditor.error("photo_editor_preview_request_error photoId=\(photoId, privacy: .private)")
                        continuation.resume(throwing: PhotoEditorImageError.loadFailed)
                        return
                    }
                    guard let image else {
                        continuation.resume(throwing: PhotoEditorImageError.loadFailed)
                        return
                    }
                    continuation.resume(returning: image)
                }
                requestBox.set(requestId)
            }
        } onCancel: {
            requestBox.cancel(using: manager)
        }
    }
}

/// Same cancellation-handoff shape as `PhotoKitAssetProvider`'s own `ImageRequestBox` — lets
/// `onCancel` reach a request id that's only known synchronously inside the completion closure.
private final class PhotoEditorImageRequestBox: @unchecked Sendable {
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
