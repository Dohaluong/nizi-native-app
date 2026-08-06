//
//  NiziPersistentModels.swift
//  Nizi
//

import SwiftData

/// The one schema used by every production Memory Discovery container. Keeping this list in one
/// place prevents a view or diagnostic entry point from constructing a container that can index
/// photos but cannot later persist its sessions/events/trips.
enum NiziPersistentModels {
    static let app: [any PersistentModel.Type] = [
        MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
        MDEventCurationResult.self, MDPhotoCurationGroup.self, MDPhotoCurationItem.self,
        MDMemoryCandidate.self, MDLocationCluster.self, MDHomeAnchor.self, MDFamiliarPlace.self,
        MDPhotoTrip.self, MDAlbumDraft.self, MDPhotoEditRecipe.self, MDCollectionEditStyle.self,
        MDPresetOverride.self, MDCustomPreset.self, MDNiziMoveImportSession.self,
        MDNiziMoveImportAsset.self, MDGoogleDrivePreparation.self
    ]

    static let memoryDiscovery: [any PersistentModel.Type] = [
        MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
        MDEventCurationResult.self, MDPhotoCurationGroup.self, MDPhotoCurationItem.self,
        MDMemoryCandidate.self, MDLocationCluster.self, MDHomeAnchor.self, MDFamiliarPlace.self,
        MDPhotoTrip.self
    ]
}
