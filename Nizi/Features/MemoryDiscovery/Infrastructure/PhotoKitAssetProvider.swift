//
//  PhotoKitAssetProvider.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Photos
import CoreGraphics

/// The only place in Memory Discovery allowed to call PHAsset/PHImageManager directly.
/// See docs/modules/memory-discovery/ARCHITECTURE.md § 6.2.
final class PhotoKitAssetProvider: PhotoAssetProvider {
    private let imageManager = PHCachingImageManager()
    /// Keyed `assetID-widthxheight-fill|fit`. Only ever holds resized thumbnails, never
    /// originals — checked before every PhotoKit request so a photo already seen this session
    /// shows with zero round trip. Content mode is part of the key so a `.fill` (cropped) and a
    /// `.fit` (letterboxed) request at the same pixel size can never be confused for each other.
    private let memoryCache = NSCache<NSString, PlatformImage>()

    func scanSummary() async throws -> LibraryScanSummary {
        let start = Date()

        let result = PHAsset.fetchAssets(with: PHFetchOptions())

        var photoCount = 0
        var videoCount = 0
        var withDateCount = 0
        var withGPSCount = 0
        var oldest: Date?
        var newest: Date?

        result.enumerateObjects { asset, _, _ in
            switch asset.mediaType {
            case .image:
                photoCount += 1
            case .video:
                videoCount += 1
            default:
                break
            }
            if let date = asset.creationDate {
                withDateCount += 1
                if oldest == nil || date < oldest! { oldest = date }
                if newest == nil || date > newest! { newest = date }
            }
            if asset.location != nil {
                withGPSCount += 1
            }
        }

        let duration = Date().timeIntervalSince(start)
        NiziLogger.discovery.info("scan_summary_completed total=\(result.count, privacy: .public) durationSeconds=\(duration, format: .fixed(precision: 2), privacy: .public)")

        return LibraryScanSummary(
            totalCount: result.count,
            photoCount: photoCount,
            videoCount: videoCount,
            withDateCount: withDateCount,
            withGPSCount: withGPSCount,
            oldestCreationDate: oldest,
            newestCreationDate: newest,
            scanDuration: duration
        )
    }

    func fetchSampleAssets(limit: Int) async throws -> [PhotoAssetSummaryItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit

        let result = PHAsset.fetchAssets(with: options)

        var items: [PhotoAssetSummaryItem] = []
        items.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            items.append(
                PhotoAssetSummaryItem(
                    id: asset.localIdentifier,
                    creationDate: asset.creationDate,
                    mediaType: PhotoMediaType(asset.mediaType),
                    hasLocation: asset.location != nil,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight
                )
            )
        }
        return items
    }

    func totalAssetCount(dateRanges: [DateRangeFilter]) async throws -> Int {
        let options = PHFetchOptions()
        options.predicate = Self.predicate(for: dateRanges)
        return PHAsset.fetchAssets(with: options).count
    }

    func fetchAssetRecords(offset: Int, limit: Int, dateRanges: [DateRangeFilter]) async throws -> [PhotoAssetRecord] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = Self.predicate(for: dateRanges)
        let result = PHAsset.fetchAssets(with: options)

        guard offset < result.count else { return [] }
        let upperBound = min(offset + limit, result.count)
        let assets = result.objects(at: IndexSet(offset..<upperBound))

        return assets.map(PhotoAssetRecord.init)
    }

    func requestThumbnail(
        assetID: String,
        targetSize: CGSize,
        networkAccessAllowed: Bool,
        deliveryMode: ThumbnailDeliveryMode,
        contentMode: ThumbnailContentMode
    ) async throws -> PlatformImage {
        let cacheKey = Self.cacheKey(assetID: assetID, targetSize: targetSize, contentMode: contentMode)
        if let cached = memoryCache.object(forKey: cacheKey) {
            NiziLogger.discovery.notice("thumbnail_cache_hit key=\(cacheKey, privacy: .private)")
            return cached
        }

        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            NiziLogger.discovery.error("thumbnail_asset_fetch_failed assetID=\(assetID, privacy: .private)")
            throw PhotoAssetProviderError.assetUnavailable
        }
        NiziLogger.discovery.notice("thumbnail_request_start key=\(cacheKey, privacy: .private) networkAllowed=\(networkAccessAllowed, privacy: .public)")

        let options = PHImageRequestOptions()
        // `.fastFormat`/`.highQualityFormat` are both single-callback modes — unlike
        // `.opportunistic`, which can call the completion handler twice and would break the
        // single-resume `withCheckedThrowingContinuation` below. A single bounded-size request is
        // also simply faster and more predictable than opportunistic delivery at full resolution
        // — see docs/sprint/SPRINT-005B-preview.md's follow-up on the three-tier image model.
        options.deliveryMode = deliveryMode == .fast ? .fastFormat : .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = networkAccessAllowed
        options.isSynchronous = false

        let requestBox = ImageRequestBox()
        let manager = imageManager
        let cache = memoryCache
        let phContentMode: PHImageContentMode = contentMode == .fill ? .aspectFill : .aspectFit

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestID = manager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: phContentMode,
                    options: options
                ) { image, info in
                    let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                    if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                        NiziLogger.discovery.notice("thumbnail_request_cancelled key=\(cacheKey, privacy: .private)")
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    if let error = info?[PHImageErrorKey] as? Error {
                        NiziLogger.discovery.error("thumbnail_request_error key=\(cacheKey, privacy: .private) error=\(String(describing: error), privacy: .public)")
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let image else {
                        let isInCloud = info?[PHImageResultIsInCloudKey] as? Bool ?? false
                        NiziLogger.discovery.error("thumbnail_request_no_image key=\(cacheKey, privacy: .private) isInCloud=\(isInCloud, privacy: .public)")
                        continuation.resume(
                            throwing: isInCloud ? PhotoAssetProviderError.iCloudDownloadRequired : PhotoAssetProviderError.thumbnailUnavailable
                        )
                        return
                    }
                    NiziLogger.discovery.notice("thumbnail_request_completed key=\(cacheKey, privacy: .private) isDegraded=\(isDegraded, privacy: .public)")
                    cache.setObject(image, forKey: cacheKey)
                    continuation.resume(returning: image)
                }
                requestBox.set(requestID)
            }
        } onCancel: {
            requestBox.cancel(using: manager)
        }
    }

    func cachedThumbnail(assetID: String, targetSize: CGSize, contentMode: ThumbnailContentMode) -> PlatformImage? {
        memoryCache.object(forKey: Self.cacheKey(assetID: assetID, targetSize: targetSize, contentMode: contentMode))
    }

    private static func cacheKey(assetID: String, targetSize: CGSize, contentMode: ThumbnailContentMode) -> NSString {
        let modeTag = contentMode == .fill ? "fill" : "fit"
        return "\(assetID)-\(Int(targetSize.width))x\(Int(targetSize.height))-\(modeTag)" as NSString
    }

    private static func predicate(for dateRanges: [DateRangeFilter]) -> NSPredicate? {
        guard !dateRanges.isEmpty else { return nil }
        let subpredicates = dateRanges.map { range in
            NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", range.start as NSDate, range.end as NSDate)
        }
        return NSCompoundPredicate(orPredicateWithSubpredicates: subpredicates)
    }

    func prefetchThumbnails(assetIDs: [String], targetSize: CGSize, contentMode: ThumbnailContentMode, networkAccessAllowed: Bool) {
        NiziLogger.discovery.notice("thumbnail_prefetch_start count=\(assetIDs.count, privacy: .public) size=\(Int(targetSize.width), privacy: .public)x\(Int(targetSize.height), privacy: .public) networkAllowed=\(networkAccessAllowed, privacy: .public)")
        imageManager.startCachingImages(
            for: Self.fetchPHAssets(ids: assetIDs),
            targetSize: targetSize,
            contentMode: contentMode == .fill ? .aspectFill : .aspectFit,
            options: Self.cachingOptions(networkAccessAllowed: networkAccessAllowed)
        )
    }

    func stopPrefetchingThumbnails(assetIDs: [String], targetSize: CGSize, contentMode: ThumbnailContentMode, networkAccessAllowed: Bool) {
        imageManager.stopCachingImages(
            for: Self.fetchPHAssets(ids: assetIDs),
            targetSize: targetSize,
            contentMode: contentMode == .fill ? .aspectFill : .aspectFit,
            options: Self.cachingOptions(networkAccessAllowed: networkAccessAllowed)
        )
    }

    /// `PHImageRequestOptions()` defaults to `isNetworkAccessAllowed = false` — passing `nil` (the
    /// old behavior) silently made `startCachingImages` a no-op for any iCloud-only asset, which
    /// is exactly what defeated the viewer's window preheat: swiping ahead of a never-downloaded
    /// photo would look "preheated" but PhotoKit had never actually started fetching it, so the
    /// real download only began once the page itself requested it. Delivery mode matches the tier
    /// this caching request is for, so the eventual real `requestImage` call is more likely to hit
    /// PhotoKit's own cache instead of redoing work.
    private static func cachingOptions(networkAccessAllowed: Bool) -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = networkAccessAllowed
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        return options
    }

    private static func fetchPHAssets(ids: [String]) -> [PHAsset] {
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }
}

/// Thread-safe holder so the `onCancel` handler can reach the request ID captured
/// synchronously inside the continuation closure.
private final class ImageRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var requestID: PHImageRequestID?

    func set(_ id: PHImageRequestID) {
        lock.lock()
        requestID = id
        lock.unlock()
    }

    func cancel(using manager: PHImageManager) {
        lock.lock()
        let id = requestID
        lock.unlock()
        if let id {
            manager.cancelImageRequest(id)
        }
    }
}

private extension PhotoMediaType {
    init(_ mediaType: PHAssetMediaType) {
        switch mediaType {
        case .image:
            self = .image
        case .video:
            self = .video
        case .audio:
            self = .audio
        case .unknown:
            self = .unknown
        @unknown default:
            self = .unknown
        }
    }
}

private extension PhotoAssetSourceType {
    init(_ sourceType: PHAssetSourceType) {
        if sourceType.contains(.typeCloudShared) {
            self = .shared
        } else if sourceType.contains(.typeUserLibrary) {
            self = .userLibrary
        } else {
            self = .unknown
        }
    }
}

extension PhotoAssetRecord {
    init(asset: PHAsset) {
        self.init(
            id: asset.localIdentifier,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            mediaType: PhotoMediaType(asset.mediaType),
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude,
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            burstIdentifier: asset.burstIdentifier,
            sourceType: PhotoAssetSourceType(asset.sourceType)
        )
    }
}
