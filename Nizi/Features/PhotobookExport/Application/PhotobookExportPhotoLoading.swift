//
//  PhotobookExportPhotoLoading.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/2/26.
//

import CoreGraphics
import Photos

/// One awaited, final-quality `CGImage` per call — never the progressive `.degraded`-then-final
/// stream the live editor grid wants, since export only ever draws the finished page once. Talks
/// to `PHImageManager` directly (not `AlbumPhotoProviding`/`ApplePhotosAlbumPhotoProvider`, the
/// live editor's own path) so export can ask for `resizeMode = .exact` without changing the
/// editor's own `.fast` resize behavior. `onDownloadProgress` (0...1) fires only while PhotoKit is
/// genuinely fetching bytes from iCloud — `PhotobookPDFExporter` itself passes `nil` (the export
/// progress UI no longer shows a distinct downloading message, § user request), but the hook stays
/// on the protocol since it's also how tests drive multiple real suspension points per photo load.
protocol PhotobookExportPhotoLoading: Sendable {
    func loadImage(
        reference: AlbumPhotoReference,
        targetPixelSize: CGSize,
        contentMode: AlbumPhotoContentMode,
        onDownloadProgress: (@Sendable (Double) -> Void)?
    ) async throws -> CGImage
}

/// Production implementation. § requirements this directly satisfies:
/// - `isNetworkAccessAllowed = true` — iCloud-only originals are fetched, not skipped.
/// - `deliveryMode = .highQualityFormat` — PhotoKit calls the handler exactly once, with the best
///   available image; combined with the explicit `isDegraded` guard below (belt and suspenders —
///   `.highQualityFormat` shouldn't ever deliver a degraded pass, but this makes "only the final,
///   non-degraded image resumes" true by construction, not by assumption).
/// - `resizeMode = .exact` — a real resize to `targetPixelSize`, not PhotoKit's `.fast`
///   approximation (the live editor grid's own choice, appropriate there for scroll performance,
///   wrong here where the output is the final export quality).
/// - `version = .current` — whatever edits the user already made in Photos, matching what they'd
///   see if they opened this photo there themselves.
/// - The completion callback resumes the continuation *exactly once* (`hasResumed`, lock-guarded)
///   — PhotoKit's own contract allows multiple callbacks per request in general; this loader's
///   explicit job is collapsing that down to the one call site's single `await` correctly.
final class ApplePhotosPhotobookExportPhotoLoader: PhotobookExportPhotoLoading, @unchecked Sendable {
    private let imageManager: PHCachingImageManager
    private let assetResolver: any PHAssetResolving

    init(imageManager: PHCachingImageManager = PHCachingImageManager(), assetResolver: any PHAssetResolving = PHAssetRepository()) {
        self.imageManager = imageManager
        self.assetResolver = assetResolver
    }

    func loadImage(
        reference: AlbumPhotoReference,
        targetPixelSize: CGSize,
        contentMode: AlbumPhotoContentMode,
        onDownloadProgress: (@Sendable (Double) -> Void)?
    ) async throws -> CGImage {
        guard let asset = await assetResolver.asset(localIdentifier: reference.sourceIdentifier) else {
            throw AlbumPhotoProviderError.assetNotFound
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.version = .current
        options.isSynchronous = false
        if let onDownloadProgress {
            options.progressHandler = { progress, _, _, _ in
                onDownloadProgress(progress)
            }
        }

        let phContentMode: PHImageContentMode = contentMode == .fill ? .aspectFill : .aspectFit
        let manager = imageManager
        let requestBox = PhotobookImageRequestBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                let resumeGuard = PhotobookContinuationResumeGuard()
                let requestId = manager.requestImage(
                    for: asset, targetSize: targetPixelSize, contentMode: phContentMode, options: options
                ) { image, info in
                    // § "chỉ hoàn tất bằng ảnh final non-degraded" — `.highQualityFormat` should
                    // never deliver one, but a degraded pass (if it ever occurred) is simply
                    // ignored rather than resuming early with a soft preview.
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    guard !isDegraded else { return }
                    guard resumeGuard.markResumed() else { return }

                    if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let image, let cgImage = image.cgImage else {
                        continuation.resume(throwing: AlbumPhotoProviderError.requestFailed)
                        return
                    }
                    continuation.resume(returning: cgImage)
                }
                requestBox.set(requestId, manager: manager)
            }
        } onCancel: {
            requestBox.cancel()
        }
    }
}

/// Lock-protected — PhotoKit's completion handler is not guaranteed to run on any particular
/// thread, so a plain `Bool` here would be a data race.
private final class PhotobookContinuationResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    /// Returns `true` exactly once — every subsequent call (including a concurrent one) returns
    /// `false`, so the caller knows not to touch the continuation a second time.
    func markResumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return false }
        hasResumed = true
        return true
    }
}

/// Thread-safe holder so `onCancel` (which can fire from any thread) can reach the request ID
/// captured synchronously inside the continuation closure — same pattern as
/// `PhotoKitAssetProvider.swift`'s own `ImageRequestBox`/`PhotoRenderEngine.swift`'s
/// `PhotoRenderRequestBox`.
private final class PhotobookImageRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var requestId: PHImageRequestID?
    private var manager: PHImageManager?

    func set(_ id: PHImageRequestID, manager: PHImageManager) {
        lock.lock()
        requestId = id
        self.manager = manager
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let id = requestId
        let manager = self.manager
        lock.unlock()
        if let id, let manager {
            manager.cancelImageRequest(id)
        }
    }
}
