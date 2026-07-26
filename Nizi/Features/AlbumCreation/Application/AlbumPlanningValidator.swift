//
//  AlbumPlanningValidator.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Input validation (before planning starts) and final-draft validation (before a draft is
/// returned) — see docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 22 and § 30.8.
enum AlbumPlanningValidator {
    static func validateInput(_ input: AlbumPlanningInput) throws {
        guard !input.events.isEmpty else { throw AlbumPlanningError.noEvents }

        let allPhotos = input.events.flatMap(\.selectedPhotos)
        guard !allPhotos.isEmpty else { throw AlbumPlanningError.noSelectedPhotos }

        for photo in allPhotos {
            guard photo.pixelWidth > 0, photo.pixelHeight > 0 else {
                throw AlbumPlanningError.invalidPhotoDimensions(photoId: photo.id)
            }
        }

        // § 22.1 — a Spread needs at least 2 photos; a single selected photo across the whole
        // input can never form one, regardless of how many Events it's spread across.
        guard allPhotos.count >= 2 else {
            throw AlbumPlanningError.insufficientPhotos(minimum: 2, actual: allPhotos.count)
        }
    }

    static func validateDraft(_ draft: AlbumDraft, expectedPhotoCount: Int, repository: AlbumLayoutRepository) throws {
        guard !draft.coverPhotoId.isEmpty else { throw AlbumPlanningError.invalidDraft }
        guard !draft.spreads.isEmpty else { throw AlbumPlanningError.invalidDraft }

        var totalPhotos = 0
        for spread in draft.spreads {
            var spreadPhotoCount = 0
            for page in [spread.leftPage, spread.rightPage] {
                guard (1...4).contains(page.assignments.count) else { throw AlbumPlanningError.invalidDraft }
                spreadPhotoCount += page.assignments.count

                guard let layout = try? repository.layout(id: page.layoutId) else {
                    throw AlbumPlanningError.invalidDraft
                }
                let content = AlbumPageContent(
                    id: page.id, layoutId: page.layoutId, format: page.format, assignments: page.assignments
                )
                do {
                    try AlbumLayoutValidator.validateAssignments(content, layout: layout)
                } catch {
                    throw AlbumPlanningError.invalidDraft
                }
            }
            guard (2...6).contains(spreadPhotoCount) else { throw AlbumPlanningError.invalidDraft }
            totalPhotos += spreadPhotoCount
        }

        guard totalPhotos == expectedPhotoCount else { throw AlbumPlanningError.invalidDraft }
    }
}
