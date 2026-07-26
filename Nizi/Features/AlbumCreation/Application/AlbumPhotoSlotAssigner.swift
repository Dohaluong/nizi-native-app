//
//  AlbumPhotoSlotAssigner.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

struct AlbumPhotoSlotAssignmentResult {
    let assignments: [AlbumPhotoAssignment]
    let score: Double
}

/// Assigns a fixed set of photos to a specific layout's slots — one page's worth. See
/// docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 18.1, § 18.3, § 19.2, § 19.3.
protocol AlbumPhotoSlotAssigning {
    /// `photos.count` must equal `layout.slots.count` — the caller (`AlbumLayoutPairSelector`)
    /// is responsible for only ever calling this with a matching photo/layout photoCount pair.
    func assign(photos: [AlbumPlanningPhoto], to layout: AlbumPageLayout) -> AlbumPhotoSlotAssignmentResult
}

struct DefaultAlbumPhotoSlotAssigner: AlbumPhotoSlotAssigning {
    func assign(photos: [AlbumPlanningPhoto], to layout: AlbumPageLayout) -> AlbumPhotoSlotAssignmentResult {
        let slots = layout.slots.sorted { $0.order < $1.order }
        guard !photos.isEmpty, photos.count == slots.count else {
            return AlbumPhotoSlotAssignmentResult(assignments: [], score: 0)
        }

        // § 19.2 — at most 4! = 24 permutations; brute force is safe at this size.
        var bestPermutation = photos
        var bestScore = -Double.infinity
        for permutation in photos.allPermutations() {
            let candidateScore = score(permutation: permutation, slots: slots, allPhotosOnPage: photos)
            if candidateScore > bestScore {
                bestScore = candidateScore
                bestPermutation = permutation
            }
        }

        // A UUID, not `"\(slot.id)-\(index)"` — that older scheme was only unique *within one
        // Page*: two Pages using the same layout (very common) reused the same slot ids and
        // indices, producing identical `AlbumPhotoAssignment.id`s across the whole Draft. That
        // collided with anything doing a Draft-wide lookup by assignment id (e.g. the photo
        // preview's tap-to-open, `AlbumEditActionApplying.swapPhotos`'s cross-page search).
        let assignments = zip(slots, bestPermutation).map { pair in
            AlbumPhotoAssignment(id: UUID().uuidString, slotId: pair.0.id, photoId: pair.1.id)
        }
        return AlbumPhotoSlotAssignmentResult(assignments: assignments, score: bestScore)
    }

    private func score(permutation: [AlbumPlanningPhoto], slots: [AlbumLayoutSlot], allPhotosOnPage: [AlbumPlanningPhoto]) -> Double {
        var total: Double = 0
        for (index, slot) in slots.enumerated() {
            let photo = permutation[index]
            total += orientationScore(photo: photo.orientation, slot: slot.preferredOrientation)
            if slot.role == .hero {
                total += heroScore(photo: photo, photosOnPage: allPhotosOnPage)
            }
        }
        total += timelineOrderBonus(permutation: permutation, original: allPhotosOnPage)
        return total
    }

    /// § 18.1 — every (photo orientation, slot preferred orientation) pair, exhaustively.
    private func orientationScore(photo: PhotoOrientation?, slot: AlbumSlotOrientation) -> Double {
        guard let photo else { return 0 }
        if slot == .any { return 60 }
        switch (photo, slot) {
        case (.landscape, .landscape), (.portrait, .portrait), (.square, .square):
            return 100
        case (.landscape, .square), (.portrait, .square):
            return 80
        case (.square, .landscape), (.square, .portrait):
            return 65
        case (.landscape, .portrait), (.portrait, .landscape):
            return 20
        case (_, .any):
            return 60 // unreachable (handled above) — keeps the switch exhaustive
        }
    }

    /// docs/specs/SPEC-ALBUM-PLANNER.md § 6.5 — bonus toward a `hero` slot from the photo's
    /// already-computed `importance.totalScore`, normalized to 0...20 *within this page's own
    /// photos* (not read directly, since importance is roughly 0...105 unnormalized and would
    /// otherwise swamp the ±100/±80/±65/±60/±20 orientation scores it's meant to stay secondary
    /// to). Not a hard requirement that the cover photo — or even the page's most important
    /// photo — lands here if a better orientation match exists elsewhere on the page.
    private func heroScore(photo: AlbumPlanningPhoto, photosOnPage: [AlbumPlanningPhoto]) -> Double {
        let maxImportance = photosOnPage.map(\.importance.totalScore).max() ?? 0
        guard maxImportance > 0 else { return 0 }
        return 20 * (photo.importance.totalScore / maxImportance)
    }

    /// § 19.3 — soft preference for a slot-order that roughly follows the page's own photo
    /// order, without overriding a better orientation match (this is a small bonus relative to
    /// the ±100/±80/±65/±60/±20 orientation scores above, by design).
    private func timelineOrderBonus(permutation: [AlbumPlanningPhoto], original: [AlbumPlanningPhoto]) -> Double {
        guard original.count > 1 else { return 0 }
        let originalIndex = Dictionary(uniqueKeysWithValues: original.enumerated().map { ($1.id, $0) })
        var score: Double = 0
        for (slotIndex, photo) in permutation.enumerated() {
            guard let sourceIndex = originalIndex[photo.id] else { continue }
            if sourceIndex == slotIndex { score += 3 }
        }
        return score
    }
}

extension Array {
    /// All orderings of this array. O(n!) — only ever called with `n ≤ 4` here (§ 19.2).
    func allPermutations() -> [[Element]] {
        guard count > 1 else { return [self] }
        var result: [[Element]] = []
        for i in indices {
            var rest = self
            let picked = rest.remove(at: i)
            for tail in rest.allPermutations() {
                result.append([picked] + tail)
            }
        }
        return result
    }
}
