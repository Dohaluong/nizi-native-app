//
//  AlbumEditActionApplying.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Applies one `AlbumEditAction` to a Draft, returning a new Draft — the single place edit
/// logic lives (§ 18.2). `async` because `.changePageLayout`/`.removePhoto` need fresh
/// `PHAsset` metadata (orientation/dimensions) to re-run `AlbumPhotoSlotAssigner` for just the
/// affected Page — that metadata isn't persisted in `AlbumPhotoAssignment` (only the photo
/// reference is), so it's re-fetched on demand, never the full image (§ 30).
protocol AlbumEditActionApplying {
    func apply(_ action: AlbumEditAction, to draft: AlbumDraft) async throws -> AlbumDraft

    /// Replaces every reference to `oldPhotoId` — `coverPhotoId`, every Page's `assignments`
    /// across every Spread, both `heroPhotoId` fields (Page and Spread) — with `newPhoto`. Not an
    /// `AlbumEditAction` case: this isn't an interactive editing gesture with its own undo
    /// semantics, just a mechanical identifier swap following Photo Editor's "save as new asset"
    /// flow (`PhotoAssetExporting`), which writes a brand-new `PHAsset` for a photo that used to
    /// be `oldPhotoId` and needs every occurrence of the old id updated to the new one. A photo
    /// can legitimately appear in more than one place in the same Album (the cover photo is
    /// explicitly allowed to also appear inside a Page), so every occurrence is updated, not just
    /// the first match.
    func replacePhoto(oldPhotoId: String, with newPhoto: AlbumPhotoReference, in draft: AlbumDraft) -> AlbumDraft
}

struct DefaultAlbumEditActionApplying: AlbumEditActionApplying {
    private let layoutRepository: AlbumLayoutRepository
    private let slotAssigner: AlbumPhotoSlotAssigning
    private let importanceEvaluator: PhotoImportanceEvaluating
    /// Fetches fresh `PHAsset` metadata for a Page's existing photos — a closure (not a hard
    /// dependency on `PHAssetPlanningPhotoAdapter`) so this stays unit-testable without Photos.
    private let planningPhotosLookup: ([String]) -> [AlbumPlanningPhoto]

    init(
        layoutRepository: AlbumLayoutRepository = BundleAlbumLayoutRepository(),
        slotAssigner: AlbumPhotoSlotAssigning = DefaultAlbumPhotoSlotAssigner(),
        importanceEvaluator: PhotoImportanceEvaluating = DefaultPhotoImportanceEvaluator(),
        planningPhotosLookup: @escaping ([String]) -> [AlbumPlanningPhoto] = { assetIDs in
            PHAssetPlanningPhotoAdapter.planningPhotos(assetIDs: assetIDs, eventId: "edit")
        }
    ) {
        self.layoutRepository = layoutRepository
        self.slotAssigner = slotAssigner
        self.importanceEvaluator = importanceEvaluator
        self.planningPhotosLookup = planningPhotosLookup
    }

    func apply(_ action: AlbumEditAction, to draft: AlbumDraft) async throws -> AlbumDraft {
        switch action {
        case let .changeCover(photo):
            return try changeCover(photo: photo, in: draft)
        case let .changePageLayout(pageId, layoutId):
            return try await changePageLayout(pageId: pageId, layoutId: layoutId, in: draft)
        case let .swapPhotos(firstAssignmentId, secondAssignmentId):
            return try swapPhotos(firstAssignmentId, secondAssignmentId, in: draft)
        case let .updatePhotoCrop(assignmentId, crop):
            return try updatePhotoCrop(assignmentId: assignmentId, crop: crop, in: draft)
        case let .assignPhoto(assignmentId, photo):
            return try assignPhoto(assignmentId: assignmentId, photo: photo, in: draft)
        case let .removePhoto(pageId, slotId):
            return try await removePhoto(pageId: pageId, slotId: slotId, in: draft)
        case let .removeSpread(spreadId):
            return try removeSpread(spreadId: spreadId, in: draft)
        case let .updateTextBlockContent(pageId, textBlockId, text):
            return try updateTextBlockContent(pageId: pageId, textBlockId: textBlockId, text: text, in: draft)
        }
    }

    // MARK: - § 19 Change Cover

    private func changeCover(photo: AlbumPhotoReference, in draft: AlbumDraft) throws -> AlbumDraft {
        guard allPhotoIds(in: draft).contains(photo.id) else {
            throw AlbumEditError.photoNotInAlbum
        }
        var updated = draft
        updated.coverPhotoId = photo.id
        // § 19.2 — hero display + coverPhotoId only; never re-runs the Planner, never reorders Pages.
        return updated
    }

    // MARK: - § 20 Change Layout

    private func changePageLayout(pageId: String, layoutId: String, in draft: AlbumDraft) async throws -> AlbumDraft {
        guard let location = locatePage(pageId, in: draft) else { throw AlbumEditError.pageNotFound }
        let page = location.page(draft)

        let newLayout = try layoutRepository.layout(id: layoutId)
        guard newLayout.photoCount == page.assignments.count else {
            throw AlbumEditError.layoutPhotoCountMismatch
        }

        let photos = scoredPhotos(for: page)
        let orderedPhotos = page.assignments.compactMap { assignment in photos.first { $0.id == assignment.photoId } }
        let result = slotAssigner.assign(photos: orderedPhotos, to: newLayout)

        var updated = draft
        location.mutate(&updated) { page in
            page.layoutId = newLayout.id
            page.assignments = result.assignments.map { assignment in
                // Preserve each photo's own reference (filename/source) from before — the slot
                // assigner only knows about `AlbumPlanningPhoto.id`, not the richer `AlbumPhotoReference`.
                let reference = page.assignments.first { $0.photoId == assignment.photoId }?.photo
                    ?? AlbumPhotoReference(id: assignment.photoId, source: .applePhotos, sourceIdentifier: assignment.photoId, originalFilename: nil)
                return AlbumPhotoAssignment(id: assignment.id, slotId: assignment.slotId, photo: reference, crop: .centered)
            }
            page.layoutScore = nil
            page.assignmentScore = result.score
            page.heroPhotoId = newLayout.slots.first { $0.role == .hero }
                .flatMap { heroSlot in page.assignments.first { $0.slotId == heroSlot.id }?.photoId }
            // § user request "Thêm chữ" — a text block's `id` is only unique within its own
            // layout (not stable across a layout swap the way a photo's own id is), so there's no
            // equivalent to "preserve by photo id" here: every text block on the new layout starts
            // fresh/empty, and any content typed into the old layout's blocks is discarded.
            page.textAssignments = freshTextAssignments(for: newLayout, pageId: page.id)
        }
        return updated
    }

    // MARK: - § 21 Swap Photo

    private func swapPhotos(_ firstAssignmentId: String, _ secondAssignmentId: String, in draft: AlbumDraft) throws -> AlbumDraft {
        guard
            let firstLocation = locateAssignment(firstAssignmentId, in: draft),
            let secondLocation = locateAssignment(secondAssignmentId, in: draft)
        else {
            throw AlbumEditError.assignmentNotFound
        }

        var updated = draft
        let firstPhoto = firstLocation.page(updated).assignments.first { $0.id == firstAssignmentId }!.photo
        let secondPhoto = secondLocation.page(updated).assignments.first { $0.id == secondAssignmentId }!.photo

        firstLocation.mutate(&updated) { page in
            if let index = page.assignments.firstIndex(where: { $0.id == firstAssignmentId }) {
                page.assignments[index].photo = secondPhoto
                page.assignments[index].crop = .centered // § 21.2 — never carry the old photo's crop onto the new one
            }
        }
        secondLocation.mutate(&updated) { page in
            if let index = page.assignments.firstIndex(where: { $0.id == secondAssignmentId }) {
                page.assignments[index].photo = firstPhoto
                page.assignments[index].crop = .centered
            }
        }
        return updated
    }

    // MARK: - Update Photo Crop

    /// § user request — never re-scores/re-assigns anything (unlike `.swapPhotos`/
    /// `.changePageLayout`), since this only adjusts how one already-assigned photo fills its own
    /// slot — the assignment, the layout, and every other slot on the Page are untouched.
    private func updatePhotoCrop(assignmentId: String, crop: AlbumPhotoCrop, in draft: AlbumDraft) throws -> AlbumDraft {
        guard let location = locateAssignment(assignmentId, in: draft) else {
            throw AlbumEditError.assignmentNotFound
        }
        var updated = draft
        location.mutate(&updated) { page in
            if let index = page.assignments.firstIndex(where: { $0.id == assignmentId }) {
                page.assignments[index].crop = crop
            }
        }
        return updated
    }

    // MARK: - Assign Photo (crop screen "Đổi ảnh")

    /// § user request — never re-scores/re-assigns anything, same reasoning as
    /// `updatePhotoCrop`: only this one assignment's `photo` changes, nothing else on the Page.
    /// Resets `crop` to `.centered` — matches `swapPhotos`' own "never carry the old photo's crop
    /// onto the new one" convention (§ 21.2).
    private func assignPhoto(assignmentId: String, photo: AlbumPhotoReference, in draft: AlbumDraft) throws -> AlbumDraft {
        guard let location = locateAssignment(assignmentId, in: draft) else {
            throw AlbumEditError.assignmentNotFound
        }
        var updated = draft
        location.mutate(&updated) { page in
            if let index = page.assignments.firstIndex(where: { $0.id == assignmentId }) {
                page.assignments[index].photo = photo
                page.assignments[index].crop = .centered
            }
        }
        return updated
    }

    // MARK: - § 22 Remove Photo

    private func removePhoto(pageId: String, slotId: String, in draft: AlbumDraft) async throws -> AlbumDraft {
        guard let location = locatePage(pageId, in: draft) else { throw AlbumEditError.pageNotFound }
        let page = location.page(draft)
        guard page.assignments.count > 1 else {
            throw AlbumEditError.cannotRemoveLastPhotoOnPage
        }

        let remainingAssignments = page.assignments.filter { $0.slotId != slotId }
        let remainingCount = remainingAssignments.count

        let candidateLayouts = try layoutRepository.layouts(photoCount: remainingCount, format: page.format)
        guard let newLayout = candidateLayouts.first else {
            throw AlbumEditError.noCompatibleLayout
        }

        let remainingPhotoIds = remainingAssignments.map(\.photoId)
        let photos = scoredPhotos(for: page).filter { remainingPhotoIds.contains($0.id) }
        // Keep original relative order.
        let orderedPhotos = remainingPhotoIds.compactMap { id in photos.first { $0.id == id } }
        let result = slotAssigner.assign(photos: orderedPhotos, to: newLayout)

        var updated = draft
        location.mutate(&updated) { page in
            page.layoutId = newLayout.id
            page.assignments = result.assignments.map { assignment in
                let reference = remainingAssignments.first { $0.photoId == assignment.photoId }?.photo
                    ?? AlbumPhotoReference(id: assignment.photoId, source: .applePhotos, sourceIdentifier: assignment.photoId, originalFilename: nil)
                return AlbumPhotoAssignment(id: assignment.id, slotId: assignment.slotId, photo: reference, crop: .centered)
            }
            page.layoutScore = nil
            page.assignmentScore = result.score
            page.heroPhotoId = newLayout.slots.first { $0.role == .hero }
                .flatMap { heroSlot in page.assignments.first { $0.slotId == heroSlot.id }?.photoId }
            page.textAssignments = freshTextAssignments(for: newLayout, pageId: page.id)
        }
        return updated
    }

    // MARK: - Photo Editor "save as new asset" swap

    func replacePhoto(oldPhotoId: String, with newPhoto: AlbumPhotoReference, in draft: AlbumDraft) -> AlbumDraft {
        var updated = draft
        if updated.coverPhotoId == oldPhotoId {
            updated.coverPhotoId = newPhoto.id
        }
        for spreadIndex in updated.spreads.indices {
            for position in [AlbumSpreadPagePosition.left, .right] {
                PageLocation(spreadIndex: spreadIndex, position: position).mutate(&updated) { page in
                    for assignmentIndex in page.assignments.indices where page.assignments[assignmentIndex].photo.id == oldPhotoId {
                        page.assignments[assignmentIndex].photo = newPhoto
                    }
                    if page.heroPhotoId == oldPhotoId {
                        page.heroPhotoId = newPhoto.id
                    }
                }
            }
            if updated.spreads[spreadIndex].heroPhotoId == oldPhotoId {
                updated.spreads[spreadIndex].heroPhotoId = newPhoto.id
            }
        }
        return updated
    }

    // MARK: - Update Text Block Content

    /// § user request — "tap vào chữ để sửa nội dung": the only mutation that ever touches
    /// `AlbumDraftPage.textAssignments`' actual `text` (as opposed to resetting the whole array,
    /// which only `changePageLayout`/`removePhoto` do, when the set of text blocks itself changes).
    /// Inserts a fresh assignment if this text block somehow doesn't have one yet (e.g. a Page
    /// whose Draft predates this feature) rather than silently no-op'ing.
    private func updateTextBlockContent(pageId: String, textBlockId: String, text: String, in draft: AlbumDraft) throws -> AlbumDraft {
        guard let location = locatePage(pageId, in: draft) else { throw AlbumEditError.pageNotFound }
        var updated = draft
        location.mutate(&updated) { page in
            if let index = page.textAssignments.firstIndex(where: { $0.textBlockId == textBlockId }) {
                page.textAssignments[index].text = text
            } else {
                page.textAssignments.append(AlbumTextAssignment(id: "\(page.id)-\(textBlockId)", textBlockId: textBlockId, text: text))
            }
        }
        return updated
    }

    /// One empty-content `AlbumTextAssignment` per `layout.textBlocks` — see the call sites'
    /// own doc comments (`changePageLayout`/`removePhoto`) for why this always starts fresh
    /// rather than trying to carry anything over from the Page's previous layout.
    private func freshTextAssignments(for layout: AlbumPageLayout, pageId: String) -> [AlbumTextAssignment] {
        layout.textBlocks.map { AlbumTextAssignment(id: "\(pageId)-\($0.id)", textBlockId: $0.id, text: "") }
    }

    // MARK: - § 23 Remove Spread

    private func removeSpread(spreadId: String, in draft: AlbumDraft) throws -> AlbumDraft {
        guard draft.spreads.count > 1 else { throw AlbumEditError.cannotRemoveLastSpread }
        guard draft.spreads.contains(where: { $0.id == spreadId }) else { throw AlbumEditError.spreadNotFound }

        var updated = draft
        updated.spreads.removeAll { $0.id == spreadId }
        // Renumber so `order`/page `order` stay a clean, gap-free sequence (matches how
        // `AlbumDraftPlanner` originally assigns them: `index`, `index * 2`/`index * 2 + 1`).
        for (index, spread) in updated.spreads.enumerated() {
            updated.spreads[index].order = index
            updated.spreads[index].leftPage.order = index * 2
            updated.spreads[index].rightPage.order = index * 2 + 1
            _ = spread
        }
        return updated
    }

    // MARK: - Helpers

    private func allPhotoIds(in draft: AlbumDraft) -> Set<String> {
        Set(draft.spreads.flatMap { [$0.leftPage, $0.rightPage] }.flatMap { $0.assignments.map(\.photoId) })
    }

    private func scoredPhotos(for page: AlbumDraftPage) -> [AlbumPlanningPhoto] {
        let assetIDs = page.assignments.map(\.photo.sourceIdentifier)
        let photos = planningPhotosLookup(assetIDs)
        let importanceById = importanceEvaluator.evaluate(photos: photos)
        return photos.map { photo in
            var updated = photo
            updated.importance = importanceById[photo.id] ?? .zero
            return updated
        }
    }

    /// Identifies exactly one Page within a Draft (Spread index + left/right) so a mutation can
    /// be applied without duplicating "find this Page" logic at every call site.
    private struct PageLocation {
        let spreadIndex: Int
        let position: AlbumSpreadPagePosition

        func page(_ draft: AlbumDraft) -> AlbumDraftPage {
            position == .left ? draft.spreads[spreadIndex].leftPage : draft.spreads[spreadIndex].rightPage
        }

        func mutate(_ draft: inout AlbumDraft, _ body: (inout AlbumDraftPage) -> Void) {
            if position == .left {
                body(&draft.spreads[spreadIndex].leftPage)
            } else {
                body(&draft.spreads[spreadIndex].rightPage)
            }
        }
    }

    private func locatePage(_ pageId: String, in draft: AlbumDraft) -> PageLocation? {
        for (index, spread) in draft.spreads.enumerated() {
            if spread.leftPage.id == pageId { return PageLocation(spreadIndex: index, position: .left) }
            if spread.rightPage.id == pageId { return PageLocation(spreadIndex: index, position: .right) }
        }
        return nil
    }

    private func locateAssignment(_ assignmentId: String, in draft: AlbumDraft) -> PageLocation? {
        for (index, spread) in draft.spreads.enumerated() {
            if spread.leftPage.assignments.contains(where: { $0.id == assignmentId }) {
                return PageLocation(spreadIndex: index, position: .left)
            }
            if spread.rightPage.assignments.contains(where: { $0.id == assignmentId }) {
                return PageLocation(spreadIndex: index, position: .right)
            }
        }
        return nil
    }
}
