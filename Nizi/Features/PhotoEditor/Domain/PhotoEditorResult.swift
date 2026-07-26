//
//  PhotoEditorResult.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// What Photo Editor hands back to whichever screen opened it (Album, Event, or a standalone
/// caller) when it closes — PHOTO-EDITOR.md § 21. The caller uses this to decide what to refresh;
/// it never needs to know how the edit was produced.
struct PhotoEditorResult: Equatable, Sendable {
    let photoId: String
    let didSave: Bool
    /// `true` when the save also wrote/changed a `CollectionEditStyle` for this photo's Album or
    /// Event (Bước 8/9) — always `false` for a standalone edit or a "just this photo" save.
    let collectionStyleChanged: Bool
    /// Every photo whose displayed image the caller should consider stale — just `[photoId]` for
    /// a single-photo save, or the whole collection when a style was applied to it.
    let affectedPhotoIds: [String]
    /// Non-nil only for the Album/Event "save as a new photo" flow (`PhotoAssetExporting`) — the
    /// caller must swap every reference to `photoId` (an Album assignment/cover/hero id, an Event
    /// curation item's asset id) over to this identifier instead. `nil` for a plain recipe-only
    /// save, which never creates a new asset.
    var newPhotoId: String? = nil
    /// `true` when `newPhotoId` was created *and* the original `photoId` asset was deleted from
    /// the Photos library afterward (the "overwrite" choice) — `false` for "save as copy," which
    /// keeps the original asset in the library, just no longer referenced by this Album/Event.
    var didDeleteOriginalAsset: Bool = false

    static func cancelled(photoId: String) -> PhotoEditorResult {
        PhotoEditorResult(photoId: photoId, didSave: false, collectionStyleChanged: false, affectedPhotoIds: [])
    }
}
