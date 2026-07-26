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
}
