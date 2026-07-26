//
//  AlbumDraftValidator.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Production Album-edit validation — deliberately separate from `AlbumPlanningValidator`
/// (docs/specs/SPEC-REAL-ALBUM.md § 26: "Không nên gọi nó là Planning Validator nếu dùng cho
/// Album edit production"), even though the checks overlap with `AlbumPlanningValidator
/// .validateDraft`. A failed edit must never save — the caller keeps the editing session open
/// and shows the error (§ 26).
///
/// Duplicate *photos* across the Album are intentionally not rejected here — no rule in this
/// codebase currently forbids that (the cover photo is explicitly allowed to also appear inside
/// a Page — see docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 24), so § 26's conditional
/// "không duplicate ảnh... nếu đó là quy tắc hiện tại" doesn't apply.
protocol AlbumDraftValidating {
    func validate(_ draft: AlbumDraft) throws
}

enum AlbumDraftValidator {
    static func validate(_ draft: AlbumDraft, repository: AlbumLayoutRepository) throws {
        guard !draft.coverPhotoId.isEmpty else { throw AlbumPlanningError.invalidDraft }
        guard !draft.spreads.isEmpty else { throw AlbumPlanningError.invalidDraft }

        for spread in draft.spreads {
            for page in [spread.leftPage, spread.rightPage] {
                guard (1...4).contains(page.assignments.count) else { throw AlbumPlanningError.invalidDraft }

                let layout = try repository.layout(id: page.layoutId)
                guard layout.slots.count == page.assignments.count else { throw AlbumPlanningError.invalidDraft }

                let content = AlbumPageContent(id: page.id, layoutId: page.layoutId, format: page.format, assignments: page.assignments)
                try AlbumLayoutValidator.validateAssignments(content, layout: layout)

                for assignment in page.assignments {
                    guard !assignment.photo.sourceIdentifier.isEmpty else { throw AlbumPlanningError.invalidDraft }
                }
            }
            guard (2...6).contains(spread.photoCount) else { throw AlbumPlanningError.invalidDraft }
        }
    }
}

/// Protocol-based wrapper around `AlbumDraftValidator.validate(_:repository:)`, for call sites
/// that want dependency injection rather than the static entry point directly.
struct DefaultAlbumDraftValidator: AlbumDraftValidating {
    let repository: AlbumLayoutRepository

    init(repository: AlbumLayoutRepository = BundleAlbumLayoutRepository()) {
        self.repository = repository
    }

    func validate(_ draft: AlbumDraft) throws {
        try AlbumDraftValidator.validate(draft, repository: repository)
    }
}
