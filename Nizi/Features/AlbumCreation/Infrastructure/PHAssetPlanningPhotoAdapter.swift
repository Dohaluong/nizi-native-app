//
//  PHAssetPlanningPhotoAdapter.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Photos

/// The one place `Photos`/`PHAsset` meets the Album Creation module — everything past this file
/// (`AlbumPlanningInput` and the whole Planning pipeline) never sees a `PHAsset`. See
/// docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 5: "Có thể xây adapter: PHAsset → AlbumPlanningPhoto."
///
/// Reads metadata only (dimensions, dates, favorite/location) — never requests image data, per
/// § 26.2 ("Planner chỉ cần metadata").
enum PHAssetPlanningPhotoAdapter {
    static func planningPhotos(assetIDs: [String], eventId: String) -> [AlbumPlanningPhoto] {
        guard !assetIDs.isEmpty else { return [] }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)

        var photosByID: [String: AlbumPlanningPhoto] = [:]
        fetchResult.enumerateObjects { asset, _, _ in
            photosByID[asset.localIdentifier] = AlbumPlanningPhoto(
                id: asset.localIdentifier,
                eventId: eventId,
                creationDate: asset.creationDate,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                coordinate: asset.location.flatMap { PhotoCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) },
                place: nil,
                isFavorite: asset.isFavorite,
                isEdited: (asset.value(forKey: "hasAdjustments") as? Bool) ?? false,
                burstIdentifier: asset.representsBurst ? asset.burstIdentifier : nil,
                originalFilename: PHAssetResource.assetResources(for: asset).first?.originalFilename,
                exif: nil
            )
        }

        // Preserve the caller's requested order — `PHFetchResult` enumeration order isn't
        // guaranteed to match `assetIDs`' order, and downstream chronological sorting happens
        // later anyway, but a stable 1:1 mapping here keeps this adapter predictable to test.
        return assetIDs.compactMap { photosByID[$0] }
    }
}
