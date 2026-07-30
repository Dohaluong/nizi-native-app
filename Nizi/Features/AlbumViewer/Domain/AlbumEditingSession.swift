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
    /// § user request — quick-tap a photo to pinch/pan how it fills its slot. Only ever changes
    /// `AlbumPhotoAssignment.crop` (scale/offset) — never touches the underlying `AlbumPhotoReference`
    /// or the original asset itself.
    case updatePhotoCrop(assignmentId: String, crop: AlbumPhotoCrop)
    /// § user request — "đổi ảnh" from the crop screen: replaces one assignment's photo with a
    /// different one already in the Album (picked via `AlbumPhotoPickerSheet`, same as
    /// `changeCover`). Unlike `swapPhotos` this doesn't need a second assignment to swap with —
    /// the old photo just stops being used anywhere via this slot.
    case assignPhoto(assignmentId: String, photo: AlbumPhotoReference)
    case removePhoto(pageId: String, slotId: String)
    case removeSpread(spreadId: String)
    /// § user request — quick-tap a text block to type/edit its content *and* style (alignment/
    /// font/size/weight — "cho phép chọn cỡ chữ, font, weight, căn lề ... trong modal editor"), all
    /// saved together from that one screen. `pageId` (not just `textBlockId`) is needed because
    /// `AlbumTextBlock.id` is only unique within its own layout — the same id could in principle
    /// appear on more than one Page (every Page using that same layout), so the target Page must
    /// be identified explicitly, unlike `updatePhotoCrop`/`assignPhoto` which can find their target
    /// via the globally-unique `assignmentId` alone.
    case updateTextBlock(
        pageId: String, textBlockId: String, text: String,
        horizontalAlignment: AlbumTextHorizontalAlignment, verticalAlignment: AlbumTextVerticalAlignment,
        fontFamily: AlbumTextFontFamily, fontSize: Double, fontWeight: AlbumTextFontWeight
    )
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
