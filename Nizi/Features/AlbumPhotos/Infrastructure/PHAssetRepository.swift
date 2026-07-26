//
//  PHAssetRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Photos

/// Looks up one `PHAsset` by local identifier — never scans the whole library to find it
/// (docs/specs/SPEC-REAL-ALBUM.md § 7.5).
protocol PHAssetResolving: Sendable {
    func asset(localIdentifier: String) async -> PHAsset?
}

struct PHAssetRepository: PHAssetResolving {
    func asset(localIdentifier: String) async -> PHAsset? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return fetchResult.firstObject
    }
}
