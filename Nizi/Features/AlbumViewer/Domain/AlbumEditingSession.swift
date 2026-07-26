//
//  AlbumEditingSession.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Every edit touches `workingDraft`, never the persisted `AlbumDraft` directly — Cancel just
/// discards this whole struct; Save validates `workingDraft` and persists it.
/// See docs/specs/SPEC-REAL-ALBUM.md § 18.1.
struct AlbumEditingSession {
    var workingDraft: AlbumDraft
    let originalDraft: AlbumDraft

    init(draft: AlbumDraft) {
        workingDraft = draft
        originalDraft = draft
    }

    var hasChanges: Bool {
        workingDraft != originalDraft
    }
}

/// Centralized edit vocabulary — every mutation to a Draft during editing goes through one of
/// these cases and `AlbumEditActionApplying`, never ad hoc field mutation scattered across UI
/// code (§ 18.2).
enum AlbumEditAction {
    case changeCover(photo: AlbumPhotoReference)
    case changePageLayout(pageId: String, layoutId: String)
    case swapPhotos(firstAssignmentId: String, secondAssignmentId: String)
    case removePhoto(pageId: String, slotId: String)
    case removeSpread(spreadId: String)
}

enum AlbumEditError: Error, Equatable {
    case photoNotInAlbum
    case pageNotFound
    case assignmentNotFound
    case spreadNotFound
    case layoutPhotoCountMismatch
    case cannotRemoveLastPhotoOnPage
    case cannotRemoveLastSpread
    case noCompatibleLayout
}
