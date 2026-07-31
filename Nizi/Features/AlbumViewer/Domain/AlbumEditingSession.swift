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
    /// § user request — "chức năng thêm ảnh": appends one more photo (picked from
    /// `AlbumPhotoPickerSheet`, same "already in this Album" universe `changeCover`/`assignPhoto`
    /// draw from) to a Page, re-running the slot assigner against whichever layout supports the
    /// new, larger photo count — mirrors `.removePhoto`'s own "re-resolve the layout for the new
    /// count" shape, just in the opposite direction. Throws `.noCompatibleLayout` if no layout for
    /// this format supports one more slot than the Page already has (§ "Không cho thêm nếu quá
    /// giới hạn frame ảnh").
    case addPhoto(pageId: String, photo: AlbumPhotoReference)
    /// § user request — "Cho phép xoá 1 trang chứ không phải xoá cả spread": empties just this
    /// one Page (never its Spread-sibling) back to a fully hidden, structural-padding state —
    /// unlike `.removePhoto` reaching 0, this Page then vanishes from the Viewer entirely (see
    /// `AlbumViewerItemBuilder`), the same "gone" feeling `.removeSpread` used to give, just
    /// scoped to one Page instead of two.
    case removePage(pageId: String)
    /// § user request — "Thêm trang ... tạo ra 1 trang trắng": appends one new, visible "blank"
    /// Page (`AlbumDraftPage.isBlank`) at the end of the Album — reuses the last Spread's hidden
    /// padding Page if one's available, otherwise starts a new Spread. No `pageId`/target — it
    /// always targets "the end of the Album," never an existing Page.
    case addBlankPage
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
        fontFamily: AlbumTextFontFamily, fontSize: Double, fontStyle: AlbumTextFontStyle, textColor: String
    )
    /// § user request — "trang bìa sẽ có cấu trúc như trang ruột ... chạm vào để crop ảnh": the
    /// cover photo's own crop, mirroring `updatePhotoCrop` exactly but writing to
    /// `AlbumDraft.coverPhotoCrop` instead of a content Page's assignment (the cover photo has no
    /// `AlbumPhotoAssignment` of its own to address by id).
    case updateCoverPhotoCrop(crop: AlbumPhotoCrop)
    /// § user request — "square.1.cover là layout mặc định cho ảnh bìa, sau này có thể thay layout
    /// khác": mirrors `changePageLayout`, minus `pageId` (same reasoning `updateCoverTextBlock`
    /// already documents) — resets `coverPhotoCrop`/`coverTextAssignments` exactly like
    /// `changePageLayout` resets a content Page's `assignments[].crop`/`textAssignments` (a
    /// different layout can mean a different slot shape and different text block ids).
    case changeCoverLayout(layoutId: String)
    /// § user request — "chạm vào để sửa chữ tương tự như trang khác": mirrors `updateTextBlock`
    /// exactly, minus `pageId` (the cover isn't a Page in `draft.spreads`, so there's nothing to
    /// disambiguate) — writes to `AlbumDraft.coverTextAssignments` instead.
    case updateCoverTextBlock(
        textBlockId: String, text: String,
        horizontalAlignment: AlbumTextHorizontalAlignment, verticalAlignment: AlbumTextVerticalAlignment,
        fontFamily: AlbumTextFontFamily, fontSize: Double, fontStyle: AlbumTextFontStyle, textColor: String
    )
}

enum AlbumEditError: Error, Equatable {
    case photoNotInAlbum
    case pageNotFound
    case assignmentNotFound
    case spreadNotFound
    case layoutPhotoCountMismatch
    case cannotRemoveLastSpread
    case noCompatibleLayout
}
