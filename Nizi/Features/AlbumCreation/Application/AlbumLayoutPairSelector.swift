//
//  AlbumLayoutPairSelector.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Picks which layout each page of a Spread uses, and how the Spread's photos split between
/// them — the two are decided together, not in separate passes, because a layout's fitness
/// depends on exactly which photos would land in it. See
/// docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 15, § 17, § 18, and
/// docs/specs/SPEC-MODIFY-DRAFT.md § 8, § 9 (variety context/tolerance).
///
/// `context` carries the previous Spread's choices so repeated partitions/layouts can be
/// deprioritized — it's plain input/output data, not mutable state the selector owns, so this
/// stays a pure, stateless, trivially-testable `struct` (docs/specs/SPEC-MODIFY-DRAFT.md § 9:
/// "Không cần lưu vào domain Album nếu chỉ dùng trong quá trình plan").
protocol AlbumLayoutPairSelecting {
    func selectLayoutPair(
        for photos: [AlbumPlanningPhoto],
        format: AlbumPageFormat,
        context: AlbumLayoutPlanningContext
    ) throws -> AlbumLayoutPairSelection
}

struct DefaultAlbumLayoutPairSelector: AlbumLayoutPairSelecting {
    private let repository: AlbumLayoutRepository
    private let slotAssigner: AlbumPhotoSlotAssigning

    /// docs/specs/SPEC-MODIFY-DRAFT.md § 8 — a variety-preferring candidate may only win if its
    /// *quality* score (orientation + balance + hero, no variety penalty applied) is within this
    /// many points of the best quality score seen. Keeps variety from ever beating a clearly
    /// better orientation match.
    static let varietyTolerance = 12.0

    init(repository: AlbumLayoutRepository, slotAssigner: AlbumPhotoSlotAssigning = DefaultAlbumPhotoSlotAssigner()) {
        self.repository = repository
        self.slotAssigner = slotAssigner
    }

    private struct Candidate {
        let partition: AlbumPagePartition
        let leftLayout: AlbumPageLayout
        let rightLayout: AlbumPageLayout
        let leftPhotos: [AlbumPlanningPhoto]
        let rightPhotos: [AlbumPlanningPhoto]
        /// Orientation + balance + hero — never includes the variety penalty (§ 8's "base best
        /// score" must be variety-blind, or tolerance-based selection would be circular).
        let qualityScore: Double
        /// Zero or negative.
        let varietyPenalty: Double
        var totalScore: Double { qualityScore + varietyPenalty }
    }

    func selectLayoutPair(
        for photos: [AlbumPlanningPhoto],
        format: AlbumPageFormat,
        context: AlbumLayoutPlanningContext = .empty
    ) throws -> AlbumLayoutPairSelection {
        let partitions = validPartitions(totalPhotoCount: photos.count)
        guard !partitions.isEmpty else {
            throw AlbumPlanningError.noValidSpreadPartition(photoCount: photos.count)
        }

        var candidates: [Candidate] = []
        var sawAnyCompatibleLayout = false

        for partition in partitions {
            guard
                let leftLayouts = try? repository.layouts(photoCount: partition.leftCount, format: format), !leftLayouts.isEmpty,
                let rightLayouts = try? repository.layouts(photoCount: partition.rightCount, format: format), !rightLayouts.isEmpty
            else { continue }
            sawAnyCompatibleLayout = true

            // § 19.1 — every way to choose `leftCount` of the Spread's photos for the left page
            // (remainder goes right), each side keeping the Spread's original chronological order.
            for leftPhotos in combinations(of: photos, count: partition.leftCount) {
                let leftIds = Set(leftPhotos.map(\.id))
                let rightPhotos = photos.filter { !leftIds.contains($0.id) }

                for leftLayout in leftLayouts {
                    let leftResult = slotAssigner.assign(photos: leftPhotos, to: leftLayout)
                    for rightLayout in rightLayouts {
                        let rightResult = slotAssigner.assign(photos: rightPhotos, to: rightLayout)

                        let quality = leftResult.score + rightResult.score + balanceScore(partition: partition)
                        let penalty = varietyPenalty(leftLayoutId: leftLayout.id, rightLayoutId: rightLayout.id, partition: partition, context: context)

                        candidates.append(
                            Candidate(
                                partition: partition, leftLayout: leftLayout, rightLayout: rightLayout,
                                leftPhotos: leftPhotos, rightPhotos: rightPhotos,
                                qualityScore: quality, varietyPenalty: penalty
                            )
                        )
                    }
                }
            }
        }

        guard !candidates.isEmpty else {
            if sawAnyCompatibleLayout {
                throw AlbumPlanningError.noValidSpreadPartition(photoCount: photos.count)
            }
            throw AlbumPlanningError.noCompatibleLayout(photoCount: photos.count)
        }

        // docs/specs/SPEC-MODIFY-DRAFT.md § 8 — two-step selection: find the best *quality*
        // score, keep everything within tolerance of it, then within that near-equivalent group
        // prefer whichever repeats the least.
        let baseBestQuality = candidates.map(\.qualityScore).max() ?? 0
        let nearEquivalent = candidates.filter { $0.qualityScore >= baseBestQuality - Self.varietyTolerance }

        guard var winner = nearEquivalent.first else {
            throw AlbumPlanningError.noCompatibleLayout(photoCount: photos.count)
        }
        for candidate in nearEquivalent.dropFirst() where isBetter(candidate, than: winner) {
            winner = candidate
        }

        return AlbumLayoutPairSelection(
            leftLayout: winner.leftLayout,
            rightLayout: winner.rightLayout,
            leftPhotos: winner.leftPhotos,
            rightPhotos: winner.rightPhotos,
            score: winner.totalScore
        )
    }

    /// Within the near-equivalent group: least variety penalty (i.e. most different from recent
    /// history) → higher quality score → more balanced partition → left layout ID → right layout
    /// ID → keep the first-seen candidate (stable, since generation order is itself deterministic).
    private func isBetter(_ candidate: Candidate, than current: Candidate) -> Bool {
        if candidate.varietyPenalty != current.varietyPenalty { return candidate.varietyPenalty > current.varietyPenalty }
        if candidate.qualityScore != current.qualityScore { return candidate.qualityScore > current.qualityScore }
        let candidateBalance = abs(candidate.partition.leftCount - candidate.partition.rightCount)
        let currentBalance = abs(current.partition.leftCount - current.partition.rightCount)
        if candidateBalance != currentBalance { return candidateBalance < currentBalance }
        if candidate.leftLayout.id != current.leftLayout.id { return candidate.leftLayout.id < current.leftLayout.id }
        if candidate.rightLayout.id != current.rightLayout.id { return candidate.rightLayout.id < current.rightLayout.id }
        return false
    }

    /// § 18.2 — exact lookup table, not a formula, to match the spec precisely.
    private func balanceScore(partition: AlbumPagePartition) -> Double {
        switch abs(partition.leftCount - partition.rightCount) {
        case 0: return 20
        case 1: return 15
        case 2: return 8
        case 3: return 2
        default: return 0
        }
    }

    /// Combines docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 18.4 and
    /// docs/specs/SPEC-MODIFY-DRAFT.md § 8's penalty lists:
    /// - partition repeats the immediately-previous Spread's partition: −8
    /// - partition repeats the Spread *before* that one (a 2-Spread-wide stale pattern, not just
    ///   an exact one-Spread repeat — this is this implementation's reading of "layout count
    ///   pattern giống Spread trước," which the spec doesn't give exact code for): −8
    /// - the whole pair (both layouts) repeats the immediately-previous pair: additional −10
    /// - a single page's layout repeats the same-side page from the immediately-previous Spread: −5 each
    /// - a layout appears anywhere in the last 2–3 Pages' history: −3 each
    private func varietyPenalty(
        leftLayoutId: String,
        rightLayoutId: String,
        partition: AlbumPagePartition,
        context: AlbumLayoutPlanningContext
    ) -> Double {
        var penalty: Double = 0

        if let previous = context.previousPartition, previous == partition {
            penalty -= 8
        }
        if context.recentPartitions.count > 1, context.recentPartitions[context.recentPartitions.count - 2] == partition {
            penalty -= 8
        }

        let leftRepeatsPrevious = context.previousLeftLayoutId == leftLayoutId
        let rightRepeatsPrevious = context.previousRightLayoutId == rightLayoutId
        if leftRepeatsPrevious { penalty -= 5 }
        if rightRepeatsPrevious { penalty -= 5 }
        if leftRepeatsPrevious, rightRepeatsPrevious { penalty -= 10 }

        if context.recentlyUsedLayoutIds.contains(leftLayoutId) { penalty -= 3 }
        if context.recentlyUsedLayoutIds.contains(rightLayoutId) { penalty -= 3 }

        return penalty
    }
}

/// Every size-`count` subset of `array`, preserving `array`'s original relative order within
/// each subset (never reordering) — indices are always chosen in increasing order.
func combinations<T>(of array: [T], count: Int) -> [[T]] {
    guard count > 0 else { return [[]] }
    guard array.count >= count else { return [] }
    if count == array.count { return [array] }

    var result: [[T]] = []
    for i in 0...(array.count - count) {
        let head = array[i]
        let rest = Array(array[(i + 1)...])
        for tail in combinations(of: rest, count: count - 1) {
            result.append([head] + tail)
        }
    }
    return result
}
