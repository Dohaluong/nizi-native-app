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

    static func cancelled(photoId: String) -> PhotoEditorResult {
        PhotoEditorResult(photoId: photoId, didSave: false, collectionStyleChanged: false, affectedPhotoIds: [])
    }
}
