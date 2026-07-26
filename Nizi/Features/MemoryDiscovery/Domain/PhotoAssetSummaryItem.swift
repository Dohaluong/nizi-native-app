//
//  PhotoAssetSummaryItem.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

enum PhotoMediaType: String, Equatable, Hashable {
    case image
    case video
    case audio
    case unknown
}

/// Lightweight metadata DTO for a single asset — never the `PHAsset` itself.
/// See docs/modules/memory-discovery/ARCHITECTURE.md § 6.2 on not passing `PHAsset` around the app.
struct PhotoAssetSummaryItem: Identifiable, Equatable {
    let id: String
    let creationDate: Date?
    let mediaType: PhotoMediaType
    let hasLocation: Bool
    let pixelWidth: Int
    let pixelHeight: Int
}
