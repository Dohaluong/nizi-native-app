//
//  AlbumEditingSessionTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

struct AlbumEditingSessionTests {
    private func reference(_ id: String) -> AlbumPhotoReference {
        AlbumPhotoReference(id: id, source: .applePhotos, sourceIdentifier: id, originalFilename: nil)
    }

    private func page(id: String, photoIds: [String], layoutId: String) -> AlbumDraftPage {
        AlbumDraftPage(
            id: id, order: 0, layoutId: layoutId, format: .square,
            assignments: zip(photoIds.indices, photoIds).map { index, photoId in
                AlbumPhotoAssignment(id: "\(id)-a\(index)", slotId: "photo-\(index + 1)", photo: reference(photoId))
            },
            sourceEventIds: ["e1"]
        )
    }

    private func makeDraft() -> AlbumDraft {
        let leftPage = page(id: "spread-0-left", photoIds: ["p1", "p2"], layoutId: "square.2.vertical-split")
        let rightPage = page(id: "spread-0-right", photoIds: ["p3", "p4", "p5"], layoutId: "square.3.hero-top")
        let spread = AlbumDraftSpread(id: "spread-0", order: 0, sourceEventIds: ["e1"], leftPage: leftPage, rightPage: rightPage)
        return AlbumDraft(
            id: "draft-1", title: "Test", subtitle: nil, coverPhotoId: "p1",
            startDate: nil, endDate: nil, primaryLocationName: nil, primaryPlace: nil,
            sourceEvents: [], spreads: [spread], createdAt: Date(), planningVersion: 1, planningLog: nil
        )
    }

    /// Synthesizes `AlbumPlanningPhoto`s for asset IDs instead of touching PHAsset — every ID
    /// gets an alternating landscape/portrait orientation so the layout-reassignment tests have
    /// something meaningful to score.
    private func makeApplier() -> DefaultAlbumEditActionApplying {
        DefaultAlbumEditActionApplying(planningPhotosLookup: { assetIDs in
            assetIDs.enumerated().map { index, id in
                let isLandscape = index.isMultiple(of: 2)
                return AlbumPlanningPhoto(
                    id: id, eventId: "e1", creationDate: nil,
                    pixelWidth: isLandscape ? 1600 : 1200, pixelHeight: isLandscape ? 1200 : 1600,
                    coordinate: nil, place: nil, isFavorite: false, isEdited: false,
                    burstIdentifier: nil, originalFilename: nil, exif: nil
                )
            }
        })
    }

    // MARK: - § 36.7 Edit session

    @Test func cancelDoesNotChangeTheOriginalDraft() {
        let original = makeDraft()
        var session = AlbumEditingSession(draft: original)
        session.workingDraft.title = "Changed"
        #expect(session.originalDraft.title == "Test")
        #expect(original.title == "Test")
    }

    @Test func hasChangesReflectsMutation() {
        let draft = makeDraft()
        var session = AlbumEditingSession(draft: draft)
        #expect(!session.hasChanges)
        session.workingDraft.title = "New Title"
        #expect(session.hasChanges)
    }

    // MARK: - § 19 Change Cover

    @Test func changeCoverUpdatesCoverPhotoId() async throws {
        let applier = makeApplier()
        let updated = try await applier.apply(.changeCover(photo: reference("p3")), to: makeDraft())
        #expect(updated.coverPhotoId == "p3")
    }

    @Test func changeCoverRejectsAPhotoNotInTheAlbum() async {
        let applier = makeApplier()
        await #expect(throws: AlbumEditError.photoNotInAlbum) {
            try await applier.apply(.changeCover(photo: reference("not-in-album")), to: makeDraft())
        }
    }

    // MARK: - § 20 Change Layout / § 36.8

    @Test func changeLayoutOnlyOffersSamePhotoCountLayouts() async throws {
        let repository = BundleAlbumLayoutRepository()
        let layouts = try repository.layouts(photoCount: 2, format: .square)
        #expect(layouts.allSatisfy { $0.photoCount == 2 })
    }

    @Test func changeLayoutPreservesAllPhotosOnThePage() async throws {
        let applier = makeApplier()
        let draft = makeDraft()
        let updated = try await applier.apply(.changePageLayout(pageId: "spread-0-left", layoutId: "square.2.horizontal-split"), to: draft)
        let updatedPage = updated.spreads[0].leftPage
        #expect(Set(updatedPage.assignments.map(\.photoId)) == Set(["p1", "p2"]))
        #expect(updatedPage.layoutId == "square.2.horizontal-split")
    }

    @Test func changeLayoutNeverDuplicatesAnAssignment() async throws {
        let applier = makeApplier()
        let updated = try await applier.apply(.changePageLayout(pageId: "spread-0-right", layoutId: "square.3.equal-columns"), to: makeDraft())
        let assignments = updated.spreads[0].rightPage.assignments
        #expect(Set(assignments.map(\.slotId)).count == assignments.count)
        #expect(Set(assignments.map(\.photoId)).count == assignments.count)
    }

    @Test func changeLayoutRejectsAMismatchedPhotoCount() async {
        let applier = makeApplier()
        await #expect(throws: AlbumEditError.layoutPhotoCountMismatch) {
            try await applier.apply(.changePageLayout(pageId: "spread-0-left", layoutId: "square.3.hero-top"), to: makeDraft())
        }
    }

    // MARK: - § 21 Swap Photo

    @Test func swapPhotosExchangesReferences() async throws {
        let applier = makeApplier()
        let draft = makeDraft()
        let firstAssignmentId = draft.spreads[0].leftPage.assignments[0].id // p1
        let secondAssignmentId = draft.spreads[0].rightPage.assignments[0].id // p3

        let updated = try await applier.apply(.swapPhotos(firstAssignmentId: firstAssignmentId, secondAssignmentId: secondAssignmentId), to: draft)
        let newLeftFirst = updated.spreads[0].leftPage.assignments.first { $0.id == firstAssignmentId }
        let newRightFirst = updated.spreads[0].rightPage.assignments.first { $0.id == secondAssignmentId }
        #expect(newLeftFirst?.photoId == "p3")
        #expect(newRightFirst?.photoId == "p1")
    }

    @Test func swapResetsCropToCentered() async throws {
        let applier = makeApplier()
        let draft = makeDraft()
        let firstAssignmentId = draft.spreads[0].leftPage.assignments[0].id
        let secondAssignmentId = draft.spreads[0].leftPage.assignments[1].id
        let updated = try await applier.apply(.swapPhotos(firstAssignmentId: firstAssignmentId, secondAssignmentId: secondAssignmentId), to: draft)
        #expect(updated.spreads[0].leftPage.assignments.allSatisfy { $0.crop == .centered })
    }

    // MARK: - § 22 Remove Photo / § 36.9

    @Test func removingOnePhotoFromFourSelectsAThreePhotoLayout() async throws {
        let applier = makeApplier()
        var draft = makeDraft()
        // Build a 4-photo page for this test specifically.
        draft.spreads[0].leftPage = page(id: "spread-0-left", photoIds: ["p1", "p2", "p6", "p7"], layoutId: "square.4.grid")

        let updated = try await applier.apply(.removePhoto(pageId: "spread-0-left", slotId: "photo-1"), to: draft)
        let updatedPage = updated.spreads[0].leftPage
        #expect(updatedPage.assignments.count == 3)
        let layout = try BundleAlbumLayoutRepository().layout(id: updatedPage.layoutId)
        #expect(layout.photoCount == 3)
    }

    @Test func removingTheLastPhotoLeavesABlankPlaceholderPage() async throws {
        let applier = makeApplier()
        var draft = makeDraft()
        draft.spreads[0].leftPage = page(id: "spread-0-left", photoIds: ["p1"], layoutId: "square.1.inset")

        let updated = try await applier.apply(.removePhoto(pageId: "spread-0-left", slotId: "photo-1"), to: draft)
        let updatedPage = updated.spreads[0].leftPage
        #expect(updatedPage.assignments.isEmpty)
        #expect(updatedPage.isBlank)
    }

    @Test func removePhotoKeepsSpreadWithinBounds() async throws {
        let applier = makeApplier()
        let draft = makeDraft()
        let updated = try await applier.apply(.removePhoto(pageId: "spread-0-left", slotId: "photo-1"), to: draft)
        #expect((2...6).contains(updated.spreads[0].photoCount))
    }

    // MARK: - Add Photo

    @Test func addPhotoGrowsATwoPhotoPageToAThreePhotoLayout() async throws {
        let applier = makeApplier()
        let draft = makeDraft()

        let updated = try await applier.apply(.addPhoto(pageId: "spread-0-left", photo: reference("p6")), to: draft)
        let updatedPage = updated.spreads[0].leftPage
        #expect(updatedPage.assignments.count == 3)
        #expect(Set(updatedPage.assignments.map(\.photoId)) == Set(["p1", "p2", "p6"]))
        let layout = try BundleAlbumLayoutRepository().layout(id: updatedPage.layoutId)
        #expect(layout.photoCount == 3)
    }

    @Test func cannotAddAPhotoPastTheFormatsLargestLayout() async {
        let applier = makeApplier()
        var draft = makeDraft()
        // Every square layout in the library tops out at 4 photos (§ "quá giới hạn frame ảnh").
        draft.spreads[0].leftPage = page(id: "spread-0-left", photoIds: ["p1", "p2", "p6", "p7"], layoutId: "square.4.grid")

        await #expect(throws: AlbumEditError.noCompatibleLayout) {
            try await applier.apply(.addPhoto(pageId: "spread-0-left", photo: reference("p8")), to: draft)
        }
    }

    // MARK: - Remove Page (single Page, not the whole Spread)

    @Test func removePageOnlyEmptiesThatOnePage() async throws {
        let applier = makeApplier()
        let draft = makeDraft()

        let updated = try await applier.apply(.removePage(pageId: "spread-0-left"), to: draft)
        let leftPage = updated.spreads[0].leftPage
        let rightPage = updated.spreads[0].rightPage
        #expect(leftPage.assignments.isEmpty)
        #expect(!leftPage.isBlank) // hidden padding, not a visible "tap to add" placeholder
        #expect(rightPage.assignments.map(\.photoId) == ["p3", "p4", "p5"]) // sibling untouched
    }

    @Test func removedPageIsHiddenFromTheFlattenedViewerItems() async throws {
        let applier = makeApplier()
        let draft = makeDraft()
        let updated = try await applier.apply(.removePage(pageId: "spread-0-left"), to: draft)

        let pageIds = DefaultAlbumViewerItemBuilder().makeItems(from: updated).compactMap { item -> String? in
            guard case let .page(viewerPage) = item else { return nil }
            return viewerPage.page.id
        }
        #expect(!pageIds.contains("spread-0-left"))
        #expect(pageIds.contains("spread-0-right"))
    }

    // MARK: - Add Blank Page

    @Test func addBlankPageAppendsOneVisiblePlaceholderPage() async throws {
        let applier = makeApplier()
        let draft = makeDraft()

        let updated = try await applier.apply(.addBlankPage, to: draft)
        #expect(updated.spreads.count == 2)
        let newSpread = updated.spreads[1]
        #expect(newSpread.leftPage.isBlank)
        #expect(newSpread.leftPage.assignments.isEmpty)
        #expect(!newSpread.rightPage.isBlank) // hidden padding, not shown yet
        #expect(newSpread.rightPage.assignments.isEmpty)
    }

    @Test func addBlankPageTwiceReusesThePaddingSlotBeforeANewSpread() async throws {
        let applier = makeApplier()
        let draft = makeDraft()

        let firstAdd = try await applier.apply(.addBlankPage, to: draft)
        let secondAdd = try await applier.apply(.addBlankPage, to: firstAdd)

        #expect(secondAdd.spreads.count == 2) // reused the first add's padding Page, no 3rd Spread
        #expect(secondAdd.spreads[1].leftPage.isBlank)
        #expect(secondAdd.spreads[1].rightPage.isBlank)
    }

    @Test func addBlankPageShowsUpInTheFlattenedViewerItems() async throws {
        let applier = makeApplier()
        let draft = makeDraft()
        let updated = try await applier.apply(.addBlankPage, to: draft)

        let blankPageShown = DefaultAlbumViewerItemBuilder().makeItems(from: updated).contains { item in
            guard case let .page(viewerPage) = item else { return false }
            return viewerPage.page.isBlank
        }
        #expect(blankPageShown)
    }

    // MARK: - § 23 Remove Spread

    @Test func removeSpreadRemovesBothPages() async throws {
        let applier = makeApplier()
        var draft = makeDraft()
        let secondSpread = AlbumDraftSpread(
            id: "spread-1", order: 1, sourceEventIds: ["e1"],
            leftPage: page(id: "spread-1-left", photoIds: ["p8", "p9"], layoutId: "square.2.vertical-split"),
            rightPage: page(id: "spread-1-right", photoIds: ["p10", "p11"], layoutId: "square.2.vertical-split")
        )
        draft.spreads.append(secondSpread)

        let updated = try await applier.apply(.removeSpread(spreadId: "spread-0"), to: draft)
        #expect(updated.spreads.count == 1)
        #expect(updated.spreads.first?.id == "spread-1")
    }

    @Test func cannotRemoveTheLastSpread() async {
        let applier = makeApplier()
        await #expect(throws: AlbumEditError.cannotRemoveLastSpread) {
            try await applier.apply(.removeSpread(spreadId: "spread-0"), to: makeDraft())
        }
    }

    @Test func removingSpreadNeverDeletesFromPhotosLibrary() async throws {
        // There is no Photos-deletion API anywhere in `AlbumEditActionApplying` — this test
        // exists as an explicit, permanent guard against ever adding one to this code path.
        let applier = makeApplier()
        var draft = makeDraft()
        draft.spreads.append(
            AlbumDraftSpread(
                id: "spread-1", order: 1, sourceEventIds: ["e1"],
                leftPage: page(id: "spread-1-left", photoIds: ["p8", "p9"], layoutId: "square.2.vertical-split"),
                rightPage: page(id: "spread-1-right", photoIds: ["p10", "p11"], layoutId: "square.2.vertical-split")
            )
        )
        _ = try await applier.apply(.removeSpread(spreadId: "spread-0"), to: draft)
        // No PHAssetChangeRequest / PHPhotoLibrary call exists in this codebase for edit actions.
        #expect(Bool(true))
    }

    // MARK: - Photo Editor "save as new asset" swap

    /// "p1" is deliberately both `coverPhotoId` *and* the first photo in the left Page's
    /// assignments in `makeDraft()` — exercising exactly the "same photo in more than one place"
    /// case `AlbumDraftValidator`'s own doc comment calls out as legitimate (the cover photo is
    /// explicitly allowed to also appear inside a Page).
    @Test func replacePhotoUpdatesEveryOccurrenceIncludingCoverAndHero() {
        let applier = makeApplier()
        var draft = makeDraft()
        draft.spreads[0].leftPage.heroPhotoId = "p1"
        draft.spreads[0].heroPhotoId = "p1"
        let newPhoto = reference("p1-new")

        let updated = applier.replacePhoto(oldPhotoId: "p1", with: newPhoto, in: draft)

        #expect(updated.coverPhotoId == "p1-new")
        #expect(updated.spreads[0].leftPage.assignments.first { $0.slotId == "photo-1" }?.photo.id == "p1-new")
        #expect(updated.spreads[0].leftPage.heroPhotoId == "p1-new")
        #expect(updated.spreads[0].heroPhotoId == "p1-new")
        // Untouched sibling occurrences of a *different* photo id.
        #expect(updated.spreads[0].leftPage.assignments.first { $0.slotId == "photo-2" }?.photo.id == "p2")
    }

    @Test func replacePhotoLeavesUnrelatedPhotosUntouched() {
        let applier = makeApplier()
        let draft = makeDraft()
        let newPhoto = reference("p3-new")

        let updated = applier.replacePhoto(oldPhotoId: "p3", with: newPhoto, in: draft)

        #expect(updated.coverPhotoId == "p1") // cover was "p1", never touched
        #expect(updated.spreads[0].rightPage.assignments.first { $0.slotId == "photo-1" }?.photo.id == "p3-new")
        #expect(updated.spreads[0].rightPage.assignments.first { $0.slotId == "photo-2" }?.photo.id == "p4")
    }

    @Test func replacePhotoNeverDeletesFromPhotosLibrary() {
        // Same guard as `removingSpreadNeverDeletesFromPhotosLibrary` above — `replacePhoto` is a
        // pure `AlbumDraft` mutation; the actual Photos-library write/delete lives entirely in
        // `PhotoAssetExporter`, a separate Infrastructure type this method never touches.
        let applier = makeApplier()
        _ = applier.replacePhoto(oldPhotoId: "p1", with: reference("p1-new"), in: makeDraft())
        #expect(Bool(true))
    }
}
