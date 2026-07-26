//
//  ApplePhotosAlbumPhotoProvider.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Photos

/// Production `AlbumPhotoProviding` — the only place `PHCachingImageManager` is touched
/// (docs/specs/SPEC-REAL-ALBUM.md § 8). One shared instance is meant to live for the whole Album
/// viewing session, not be recreated per photo (§ 8.1).
final class ApplePhotosAlbumPhotoProvider: AlbumPhotoProviding, @unchecked Sendable {
    private let assetResolver: PHAssetResolving
    private let imageManager: PHCachingImageManager
    private let cache: AlbumImageCache
    private let activeRequests = ActiveRequestRegistry()

    init(
        assetResolver: PHAssetResolving = PHAssetRepository(),
        imageManager: PHCachingImageManager = PHCachingImageManager(),
        cache: AlbumImageCache = AlbumImageCache()
    ) {
        self.assetResolver = assetResolver
        self.imageManager = imageManager
        self.cache = cache
    }

    func loadImage(request: AlbumPhotoRequest) -> AsyncStream<AlbumPhotoLoadState> {
        let requestId = UUID()
        let cacheKey = AlbumImageCacheKey(
            sourceIdentifier: request.reference.sourceIdentifier,
            targetPixelSize: request.targetPixelSize,
            contentMode: request.contentMode
        )

        return AsyncStream { continuation in
            // § 9 — a cache hit skips PHImageManager entirely.
            if let cached = cache.image(for: cacheKey) {
                continuation.yield(.success(cached))
                continuation.finish()
                return
            }

            continuation.yield(.loading)

            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                guard let asset = await assetResolver.asset(localIdentifier: request.reference.sourceIdentifier) else {
                    continuation.yield(.missing)
                    continuation.finish()
                    return
                }
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = true // § 8.3 — required for iCloud-only assets
                options.resizeMode = .fast
                options.deliveryMode = Self.phDeliveryMode(for: request.deliveryMode)
                options.version = .current
                options.progressHandler = { _, _, _, _ in
                    // Progress is intentionally not surfaced as a distinct `AlbumPhotoLoadState`
                    // case this sprint (§ 8.3 allows keeping it in the ViewModel/omitting it) —
                    // `.loading`/`.degraded` already cover "something is happening."
                }

                let phContentMode: PHImageContentMode = request.contentMode == .fill ? .aspectFill : .aspectFit

                let phRequestId = self.imageManager.requestImage(
                    for: asset, targetSize: request.targetPixelSize, contentMode: phContentMode, options: options
                ) { [weak self] image, info in
                    guard let self else { return }
                    let wasCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                    if wasCancelled {
                        continuation.finish()
                        return
                    }
                    guard let image else {
                        continuation.yield(.failure(.requestFailed))
                        continuation.finish()
                        return
                    }
                    // § 8.4 — degraded is never an error; it's the fast preview.
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    if isDegraded {
                        continuation.yield(.degraded(image))
                    } else {
                        self.cache.store(image, for: cacheKey)
                        continuation.yield(.success(image))
                        continuation.finish()
                        self.activeRequests.remove(requestId)
                    }
                }
                self.activeRequests.register(requestId, phRequestId: phRequestId, imageManager: self.imageManager)
            }

            // § 8.5 — the view disappearing cancels the SwiftUI `.task` iterating this stream,
            // which ends the stream, which fires `onTermination` here: the underlying
            // `PHImageManager` request is cancelled synchronously, not left running.
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                self?.activeRequests.cancel(requestId)
            }
        }
    }

    func cancelRequest(for requestId: UUID) async {
        activeRequests.cancel(requestId)
    }

    private static func phDeliveryMode(for mode: AlbumPhotoDeliveryMode) -> PHImageRequestOptionsDeliveryMode {
        switch mode {
        case .fast: return .fastFormat
        case .opportunistic: return .opportunistic
        case .highQuality: return .highQualityFormat
        }
    }
}

/// Correlates our own request IDs with `PHImageRequestID`s. Lock-protected, not an actor —
/// `AsyncStream.onTermination` is a synchronous, non-async closure, so cancellation from there
/// can't `await` an actor.
private final class ActiveRequestRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [UUID: (requestId: PHImageRequestID, imageManager: PHCachingImageManager)] = [:]

    func register(_ id: UUID, phRequestId: PHImageRequestID, imageManager: PHCachingImageManager) {
        lock.lock()
        entries[id] = (phRequestId, imageManager)
        lock.unlock()
    }

    func remove(_ id: UUID) {
        lock.lock()
        entries.removeValue(forKey: id)
        lock.unlock()
    }

    func cancel(_ id: UUID) {
        lock.lock()
        let entry = entries.removeValue(forKey: id)
        lock.unlock()
        if let entry {
            entry.imageManager.cancelImageRequest(entry.requestId)
        }
    }
}
