//
//  IndexedAsset.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// A row read back from the Local Memory Index (not from PhotoKit) — what
/// `EventDiscoveryEngine` clusters over. Only ever `.available`/`.indexed` assets
/// with a known `creationDate` are eligible; see `LocalAssetRepository.fetchClusterableAssets()`.
struct IndexedAsset: Identifiable, Equatable {
    let id: String
    let creationDate: Date
    let latitude: Double?
    let longitude: Double?
    let isFavorite: Bool
    let isScreenshot: Bool
    let burstIdentifier: String?
    let mediaType: PhotoMediaType
    let pixelWidth: Int
    let pixelHeight: Int

    /// Explicit instead of relying on Swift's generated memberwise initializer: this keeps the
    /// existing call sites source-compatible while exposing dimensions for pre-layout masonry.
    init(
        id: String,
        creationDate: Date,
        latitude: Double?,
        longitude: Double?,
        isFavorite: Bool,
        isScreenshot: Bool,
        burstIdentifier: String?,
        mediaType: PhotoMediaType,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0
    ) {
        self.id = id
        self.creationDate = creationDate
        self.latitude = latitude
        self.longitude = longitude
        self.isFavorite = isFavorite
        self.isScreenshot = isScreenshot
        self.burstIdentifier = burstIdentifier
        self.mediaType = mediaType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}
