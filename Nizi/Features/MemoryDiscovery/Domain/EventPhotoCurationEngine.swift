//
//  EventPhotoCurationEngine.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Pure, deterministic selection logic — no Vision, no PhotoKit, no persistence. Takes already
/// -analyzed, already-clustered photos (Infrastructure's job) and decides what to keep.
/// See docs/sprint/SPRINT-005B.md § 9, § 13, § 14.
enum EventPhotoCurationEngine {
    struct Configuration: Equatable {
        /// Below this composite score, a cluster contributes nothing — § 13 "Nhóm chất lượng thấp".
        var lowQualityFloor: Double = 0.25
        /// A cluster with more than this many photos may get a second pick if the runner-up
        /// is close in score and far enough in time to plausibly be a different moment.
        var largeBurstSize: Int = 5
        var largeBurstRunnerUpScoreMargin: Double = 0.15
        var largeBurstRunnerUpMinTimeGapSeconds: TimeInterval = 8
        /// Only trim when selection overshoots the reference range by this much — § 14 is
        /// explicit that the range is a soft target, not a hard limit.
        var overSelectionCeilingMultiplier: Double = 1.5
        /// Consecutive photos within this many seconds of each other belong to the same displayed
        /// group ("moment"); a bigger gap starts a new one. Deliberately much tighter than
        /// `EventDiscoveryConfig.tightGapMinutes` (which decides session/event boundaries, not
        /// display grouping) — this is purely about how the curated grid visually clusters photos
        /// within one event. Matches `VisionEventPhotoAnalyzer`'s near-duplicate time-gap window,
        /// since a near-duplicate cluster can't span a moment boundary anyway.
        var momentGroupMaxGapSeconds: TimeInterval = 60

        static let `default` = Configuration()
    }

    static func curate(
        analyzedPhotos: [AnalyzedPhoto],
        photoEventID: UUID,
        sourceAssetCount: Int,
        algorithmVersion: Int,
        config: Configuration = .default,
        now: Date = Date()
    ) -> EventCurationResult {
        let sorted = analyzedPhotos.sorted { $0.creationDate < $1.creationDate }
        let sessionBuckets = Dictionary(grouping: sorted) { $0.sessionID?.uuidString ?? "none" }
        let orderedKeys = sessionBuckets.keys.sorted { lhs, rhs in
            (sessionBuckets[lhs]?.first?.creationDate ?? .distantPast)
                < (sessionBuckets[rhs]?.first?.creationDate ?? .distantPast)
        }

        var groups: [PhotoCurationGroup] = []
        for key in orderedKeys {
            guard let sessionPhotos = sessionBuckets[key], !sessionPhotos.isEmpty else { continue }
            for moment in splitIntoMoments(sessionPhotos, maxGapSeconds: config.momentGroupMaxGapSeconds) {
                groups.append(
                    PhotoCurationGroup(
                        id: UUID(),
                        sessionID: moment.first?.sessionID,
                        startDate: moment.first!.creationDate,
                        endDate: moment.last!.creationDate,
                        sortOrder: groups.count,
                        items: selectWithinGroup(photos: moment, config: config)
                    )
                )
            }
        }

        balanceAcrossEvent(groups: &groups, sourceAssetCount: sourceAssetCount, config: config)

        return EventCurationResult(
            photoEventID: photoEventID,
            status: .completed,
            algorithmVersion: algorithmVersion,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            sourceAssetCount: sourceAssetCount,
            errorMessage: nil,
            groups: groups
        )
    }

    // MARK: - Moment splitting (display grouping within a session)

    /// Splits one session's chronologically-sorted photos into runs where consecutive photos are
    /// never more than `maxGapSeconds` apart — e.g. two photos 30 seconds apart are the same
    /// moment/group; a 5-minute gap starts a new one, even within the same overall session.
    private static func splitIntoMoments(_ photos: [AnalyzedPhoto], maxGapSeconds: TimeInterval) -> [[AnalyzedPhoto]] {
        guard var current = photos.first.map({ [$0] }) else { return [] }
        var moments: [[AnalyzedPhoto]] = []

        for photo in photos.dropFirst() {
            let gapSeconds = photo.creationDate.timeIntervalSince(current.last!.creationDate)
            if gapSeconds <= maxGapSeconds {
                current.append(photo)
            } else {
                moments.append(current)
                current = [photo]
            }
        }
        moments.append(current)
        return moments
    }

    // MARK: - Per-cluster selection (§ 12, § 13)

    private static func selectWithinGroup(photos: [AnalyzedPhoto], config: Configuration) -> [PhotoCurationItem] {
        let clusters = Dictionary(grouping: photos, by: \.similarityClusterID)
        var selectedIDs = Set<String>()

        for clusterPhotos in clusters.values {
            // Screenshots and document/whiteboard/receipt-style photos are never the algorithm's
            // own pick — see docs/sprint/SPRINT-005B-TODO.md item 7. If a whole cluster is made
            // of nothing else, it simply contributes no selection; every photo in it still shows
            // up (unselected) in the grid, and the user can always select one manually.
            let eligible = clusterPhotos.filter { !$0.isScreenshot && !$0.isDocument }
            let ranked = eligible.sorted { $0.metrics.compositeScore > $1.metrics.compositeScore }
            guard let best = ranked.first, best.metrics.compositeScore >= config.lowQualityFloor else { continue }
            selectedIDs.insert(best.assetID)

            guard ranked.count > config.largeBurstSize, ranked.count > 1 else { continue }
            let runnerUp = ranked[1]
            let scoreClose = (best.metrics.compositeScore - runnerUp.metrics.compositeScore) <= config.largeBurstRunnerUpScoreMargin
            let farEnoughApart = abs(runnerUp.creationDate.timeIntervalSince(best.creationDate)) >= config.largeBurstRunnerUpMinTimeGapSeconds
            if scoreClose, farEnoughApart, runnerUp.metrics.compositeScore >= config.lowQualityFloor {
                selectedIDs.insert(runnerUp.assetID)
            }
        }

        return photos.enumerated().map { index, photo in
            let isSelected = selectedIDs.contains(photo.assetID)
            return PhotoCurationItem(
                id: UUID(),
                assetID: photo.assetID,
                sortOrder: index,
                qualityScore: Int((photo.metrics.compositeScore * 100).rounded()),
                similarityClusterID: photo.similarityClusterID,
                isSuggested: isSelected,
                isSelected: isSelected,
                selectionSource: .systemSuggested
            )
        }
    }

    // MARK: - Event-level balancing (§ 14)

    static func targetRange(forSourceAssetCount count: Int) -> ClosedRange<Int> {
        switch count {
        case ..<50: 8...20
        case 50..<150: 15...30
        case 150..<300: 20...40
        default: 30...60
        }
    }

    /// A light touch: never force-adds when under the reference range (§ 14 explicitly says not
    /// to pad a selection just to hit a number), only trims when well past it, and protects the
    /// last remaining selected item in a group from being trimmed purely for a global cap.
    private static func balanceAcrossEvent(
        groups: inout [PhotoCurationGroup],
        sourceAssetCount: Int,
        config: Configuration
    ) {
        let ceiling = Int(Double(targetRange(forSourceAssetCount: sourceAssetCount).upperBound) * config.overSelectionCeilingMultiplier)
        var totalSelected = groups.reduce(0) { $0 + $1.suggestedCount }
        guard totalSelected > ceiling else { return }

        struct Ref {
            let groupIndex: Int
            let itemIndex: Int
            let score: Int
        }

        var refs: [Ref] = []
        for (groupIndex, group) in groups.enumerated() {
            for (itemIndex, item) in group.items.enumerated() where item.isSelected {
                refs.append(Ref(groupIndex: groupIndex, itemIndex: itemIndex, score: item.qualityScore))
            }
        }
        refs.sort { $0.score < $1.score }

        for ref in refs {
            guard totalSelected > ceiling else { break }
            guard groups[ref.groupIndex].suggestedCount > 1 else { continue }
            groups[ref.groupIndex].items[ref.itemIndex].isSelected = false
            totalSelected -= 1
        }
    }
}
