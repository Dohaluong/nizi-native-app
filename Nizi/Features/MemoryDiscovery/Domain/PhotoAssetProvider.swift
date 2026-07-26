//
//  PhotoAssetProvider.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation
import CoreGraphics

/// The only interface Presentation/Application should use to read from Photos.
/// See docs/modules/memory-discovery/ARCHITECTURE.md § 6.2.
protocol PhotoAssetProvider {
    func scanSummary() async throws -> LibraryScanSummary
    func fetchSampleAssets(limit: Int) async throws -> [PhotoAssetSummaryItem]
    func requestThumbnail(
        assetID: String,
        targetSize: CGSize,
        networkAccessAllowed: Bool,
        deliveryMode: ThumbnailDeliveryMode,
        contentMode: ThumbnailContentMode
    ) async throws -> PlatformImage

    /// Synchronous in-memory lookup only — never triggers a PhotoKit request. Lets a view show an
    /// already-fetched image instantly (e.g. reopening a photo just viewed) with zero round trip.
    /// Must match the exact `targetSize`/`contentMode` of a prior `requestThumbnail` call to hit.
    func cachedThumbnail(assetID: String, targetSize: CGSize, contentMode: ThumbnailContentMode) -> PlatformImage?

    /// Total assets currently matched by the library fetch — used to size a batch scan.
    /// Empty `dateRanges` means the whole library.
    func totalAssetCount(dateRanges: [DateRangeFilter]) async throws -> Int
    /// A page of full metadata records, ascending by `creationDate`, for the Library Scanner to index.
    /// `offset` is relative to the filtered result set when `dateRanges` is non-empty.
    func fetchAssetRecords(offset: Int, limit: Int, dateRanges: [DateRangeFilter]) async throws -> [PhotoAssetRecord]

    /// Hints that these assets will likely be requested soon, so the system can start warming
    /// its own thumbnail cache ahead of time. Fire-and-forget — never throws, never blocks.
    ///
    /// `networkAccessAllowed` must be `true` for this to do anything useful for an iCloud-only
    /// asset — PhotoKit's caching options default to no network access, which silently makes a
    /// preheat call a no-op for exactly the assets it most needs to help with. The full-screen
    /// viewer's window preheat must pass `true`; the grid's thumbnail preheat can stay `false`
    /// (small local thumbnails are always available on-device without a network round trip).
    func prefetchThumbnails(assetIDs: [String], targetSize: CGSize, contentMode: ThumbnailContentMode, networkAccessAllowed: Bool)
    /// Releases a prefetch hint — call when the assets are no longer expected to be needed soon
    /// (e.g. the screen that requested them is going away), so the cache doesn't grow unbounded.
    /// Must be called with the exact same `networkAccessAllowed` value used to start it, or
    /// PhotoKit won't recognize it as the same registration to release.
    func stopPrefetchingThumbnails(assetIDs: [String], targetSize: CGSize, contentMode: ThumbnailContentMode, networkAccessAllowed: Bool)
}

enum PhotoAssetProviderError: Error {
    case assetUnavailable
    case thumbnailUnavailable
    case iCloudDownloadRequired
}
