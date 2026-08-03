//
//  PhotoAssetRecord.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// What Photos can tell us about where an asset came from.
/// Narrower than docs/database/memory-discovery.md § 4's `source_type` (drops `cloud`) because
/// `PHAssetSourceType` doesn't expose that distinction reliably — better to omit it than fabricate it.
enum PhotoAssetSourceType: String, Equatable {
    case userLibrary
    case shared
    case unknown
}

/// Full metadata row PhotoKit can give us for one asset — enough to build a `md_local_asset` row.
/// Never carries a `PHAsset` reference; see docs/modules/memory-discovery/ARCHITECTURE.md § 6.2.
struct PhotoAssetRecord: Identifiable, Equatable {
    let id: String
    let creationDate: Date?
    let modificationDate: Date?
    let mediaType: PhotoMediaType
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let latitude: Double?
    let longitude: Double?
    let isFavorite: Bool
    let isHidden: Bool
    let isScreenshot: Bool
    let burstIdentifier: String?
    let sourceType: PhotoAssetSourceType

    /// PhotoKit occasionally reports a newly-created import before its `creationDate` has been
    /// materialized. Keep the trusted import date in the local index instead of losing the asset
    /// from chronological event/detail views.
    func withCreationDateFallback(_ fallback: Date?) -> PhotoAssetRecord {
        guard creationDate == nil, let fallback else { return self }
        return PhotoAssetRecord(
            id: id,
            creationDate: fallback,
            modificationDate: modificationDate,
            mediaType: mediaType,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            duration: duration,
            latitude: latitude,
            longitude: longitude,
            isFavorite: isFavorite,
            isHidden: isHidden,
            isScreenshot: isScreenshot,
            burstIdentifier: burstIdentifier,
            sourceType: sourceType
        )
    }
}
