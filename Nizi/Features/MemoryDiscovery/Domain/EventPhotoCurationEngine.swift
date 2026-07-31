//
//  EventPhotoCurationEngine.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Pure, deterministic selection logic — no Vision, no PhotoKit, no persistence. Takes already
/// -analyzed, already-clustered photos (Infrastructure's job) and decides what to keep.
/// See docs/sprint/SPRINT-005B.md § 9, § 13, § 14, and docs/sprint/SPRINT-SMART-EVENT-HIGHLIGHTS.md.
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

        /// Quality Gate (SPRINT-SMART-EVENT-HIGHLIGHTS.md § 18-22) — a hard usability floor
        /// *before* auto-selection, separate from `compositeScore` ranking. Starting points, not
        /// tuned against a real library yet — see § 58-59's real-library tuning workflow. Never
        /// gates on `faceScore` (§ 20): a landscape/no-person photo is fully valid.
        var minimumUsableSharpness: Double = 0.12
        var minimumUsableExposure: Double = 0.15
        /// A Favorite gets a lower (not zero) floor — moderately blurred/underexposed still
        /// passes, only a genuinely broken image doesn't (§ 22). Separate constants, not a
        /// multiplier of the non-favorite floor, so each is independently tunable from
        /// Diagnostics without coupling their ratio.
        var minimumUsableSharpnessForFavorite: Double = 0.04
        var minimumUsableExposureForFavorite: Double = 0.05

        /// Global Duplicate Suppression (§ 27-32) — deliberately more conservative than
        /// `VisionEventPhotoAnalyzer`'s local `nearDuplicateDistanceThreshold` (0.3): the goal is
        /// "same subject/pose/background," not "same general theme" (§ 30 — two different beach
        /// photos should not collapse into one just because they're both a beach). Lowered from an
        /// initial 0.2 — that was suppressing photos that weren't actually close enough to be the
        /// same shot, cutting into auto-selection more than intended.
        var globalSimilarityThreshold: Float = 0.15
        /// Safety cap on how many locally-selected representatives enter the pairwise global
        /// pass — never all-pairs over the full source photo set (§ 28, § 31).
        var maxGlobalCandidates: Int = 60

        /// Favorite priority (§ 33-36), shared by both local-cluster and global-duplicate winner
        /// resolution: a Favorite loses to a better-scoring competitor only once the gap exceeds
        /// this margin — otherwise the Favorite wins.
        var favoriteSignificantlyWorseMargin: Double = 0.15

        /// Cap on how many photos one `PhotoCurationGroup` (moment) may contribute to
        /// auto-selection, however many distinct `similarityClusterID`s it contains — expressed as
        /// a fraction of that moment's own photo count (`ceil`/`round`ed, minimum 1) rather than a
        /// flat number, so a 3-photo moment and a 40-photo moment don't share the same ceiling.
        /// Before any cap existed, a moment full of genuinely different (non-duplicate) subjects
        /// had no limit at all — every distinct cluster nominated its own winner independently, so
        /// a moment with e.g. 20 different subjects could auto-select up to 20. This was the
        /// dominant cause of a real ~500-photo Event ending up with ~400 selected despite a
        /// nominal 30...60 target. Never applied to `userAdded` items — `applyPreservedUserOverrides`
        /// runs after this and unconditionally restores any user-added photo regardless of count.
        /// Raised from an initial 0.3 — that was cutting real, non-duplicate variety out of larger
        /// moments more than intended.
        var momentAutoSelectRatio: Double = 0.5

        /// Off by default: there is no required final photo count for an Event — auto-selection
        /// is whatever survives the Quality Gate, near-duplicate clustering, Global Duplicate
        /// Suppression, and the per-moment cap above, however many or few that is. When `true`,
        /// `finalize` additionally trims toward `targetRange(forSourceAssetCount:)` (soft ceiling,
        /// plus a hard escalation for Events ≥300 photos — see `balanceAcrossEvent`); kept around,
        /// not deleted, in case a future product decision wants a bounded highlight count again.
        var enforceEventWideCeiling: Bool = false

        static let `default` = Configuration()
    }

    // MARK: - Preserving manual selection across recuration (SPRINT-SMART-EVENT-HIGHLIGHTS.md § 5-8)

    /// A snapshot of the user's explicit choices on a previously-saved result, taken before that
    /// result gets replaced by a fresh curation run. `EventPhotoCurationEngine` itself never reads
    /// or writes persisted state — capturing/re-applying this is `EventPhotoCurationService`'s job
    /// (the only layer with repository access), using these two pure functions.
    struct UserOverrideSnapshot: Equatable {
        let userAddedAssetIDs: Set<String>
        let userRemovedAssetIDs: Set<String>

        static let empty = UserOverrideSnapshot(userAddedAssetIDs: [], userRemovedAssetIDs: [])
    }

    static func captureUserOverrides(from result: EventCurationResult) -> UserOverrideSnapshot {
        let items = result.groups.flatMap(\.items)
        return UserOverrideSnapshot(
            userAddedAssetIDs: Set(items.filter { $0.selectionSource == .userAdded }.map(\.assetID)),
            userRemovedAssetIDs: Set(items.filter { $0.selectionSource == .userRemoved }.map(\.assetID))
        )
    }

    /// Re-applies a prior manual selection onto a freshly-curated result — the algorithm never
    /// gets the last word over an explicit user choice (§ 42: "USER DECISION > ALGORITHM"), no
    /// matter what the quality gate, duplicate suppression, or global balancing just decided.
    /// Only ever touches assetIDs that still exist in `result`; an asset the user once added that
    /// has since left the Event is silently skipped — no orphan item is created (§ 7).
    static func applyPreservedUserOverrides(to result: EventCurationResult, overrides: UserOverrideSnapshot) -> EventCurationResult {
        guard !overrides.userAddedAssetIDs.isEmpty || !overrides.userRemovedAssetIDs.isEmpty else { return result }

        var result = result
        for groupIndex in result.groups.indices {
            for itemIndex in result.groups[groupIndex].items.indices {
                let assetID = result.groups[groupIndex].items[itemIndex].assetID
                if overrides.userAddedAssetIDs.contains(assetID) {
                    result.groups[groupIndex].items[itemIndex].isSelected = true
                    result.groups[groupIndex].items[itemIndex].selectionSource = .userAdded
                    result.groups[groupIndex].items[itemIndex].rejectionReason = nil
                } else if overrides.userRemovedAssetIDs.contains(assetID) {
                    result.groups[groupIndex].items[itemIndex].isSelected = false
                    result.groups[groupIndex].items[itemIndex].selectionSource = .userRemoved
                }
            }
        }
        return result
    }

    // MARK: - Entry points

    /// Convenience one-shot wrapper around `curateLocally` + `finalize`, kept for callers (and
    /// existing unit tests) that don't need to interleave a real Vision-backed global-duplicate
    /// pass between the two — `EventPhotoCurationService` calls the two phases separately instead
    /// so it can run `VisionEventPhotoAnalyzer.globalDuplicateGroups` in between.
    static func curate(
        analyzedPhotos: [AnalyzedPhoto],
        photoEventID: UUID,
        sourceAssetCount: Int,
        sourceAssetFingerprint: String = "",
        algorithmVersion: Int,
        globalDuplicateGroups: [String: String] = [:],
        config: Configuration = .default,
        now: Date = Date()
    ) -> EventCurationResult {
        let localGroups = curateLocally(analyzedPhotos: analyzedPhotos, config: config)
        let analyzedPhotosByAssetID = Dictionary(uniqueKeysWithValues: analyzedPhotos.map { ($0.assetID, $0) })
        return finalize(
            localGroups: localGroups,
            analyzedPhotosByAssetID: analyzedPhotosByAssetID,
            globalDuplicateGroups: globalDuplicateGroups,
            photoEventID: photoEventID,
            sourceAssetCount: sourceAssetCount,
            sourceAssetFingerprint: sourceAssetFingerprint,
            algorithmVersion: algorithmVersion,
            config: config,
            now: now
        )
    }

    /// Phase 1 — local grouping + per-cluster selection only (Quality Gate, near-duplicate
    /// clustering, burst runner-up, Favorite-aware winner pick). No global dedup, no event-wide
    /// trim yet; see `finalize` for those.
    static func curateLocally(analyzedPhotos: [AnalyzedPhoto], config: Configuration = .default) -> [PhotoCurationGroup] {
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
        return groups
    }

    /// The (already small) pool of locally-selected representatives that Global Duplicate
    /// Suppression compares pairwise — never the full source photo set (§ 28). Quality-sorted and
    /// capped at `maxGlobalCandidates` so a pathological Event can't blow up the comparison (§ 31).
    static func globalDedupCandidateAssetIDs(from localGroups: [PhotoCurationGroup], config: Configuration = .default) -> [String] {
        let selected = localGroups.flatMap(\.items).filter(\.isSelected)
        return Array(
            selected
                .sorted { $0.qualityScore > $1.qualityScore }
                .prefix(config.maxGlobalCandidates)
        ).map(\.assetID)
    }

    /// Phase 2 — applies a caller-supplied global-duplicate map (Infrastructure's job to compute,
    /// via feature prints already captured during analysis) and, only if
    /// `config.enforceEventWideCeiling` opts in, the event-wide temporal/quality trim; then
    /// assembles the final `EventCurationResult`. Manual-selection preservation
    /// (`applyPreservedUserOverrides`) is deliberately NOT called here — it runs once, in
    /// `EventPhotoCurationService`, as the unconditional last step over the whole result.
    static func finalize(
        localGroups: [PhotoCurationGroup],
        analyzedPhotosByAssetID: [String: AnalyzedPhoto],
        globalDuplicateGroups: [String: String],
        photoEventID: UUID,
        sourceAssetCount: Int,
        sourceAssetFingerprint: String = "",
        algorithmVersion: Int,
        config: Configuration = .default,
        now: Date = Date()
    ) -> EventCurationResult {
        var groups = localGroups
        applyGlobalDuplicateSuppression(
            groups: &groups,
            analyzedPhotosByAssetID: analyzedPhotosByAssetID,
            globalDuplicateGroups: globalDuplicateGroups,
            config: config
        )
        if config.enforceEventWideCeiling {
            balanceAcrossEvent(groups: &groups, analyzedPhotosByAssetID: analyzedPhotosByAssetID, sourceAssetCount: sourceAssetCount, config: config)
        }

        return EventCurationResult(
            photoEventID: photoEventID,
            status: .completed,
            algorithmVersion: algorithmVersion,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            sourceAssetCount: sourceAssetCount,
            sourceAssetFingerprint: sourceAssetFingerprint,
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

    // MARK: - Favorite-aware winner resolution (§ 33-36) — shared by local and global dedup

    private struct DuplicateCandidate {
        let assetID: String
        let compositeScore: Double
        let isFavorite: Bool
    }

    /// Picks the preferred of two candidates that are duplicates of each other (same
    /// near-duplicate cluster, or judged a global visual duplicate): a Favorite wins unless the
    /// other candidate scores significantly higher (`favoriteSignificantlyWorseMargin`);
    /// otherwise the higher composite score wins; ties break deterministically by assetID so
    /// results are reproducible. Never consulted for a candidate that failed the Quality Gate —
    /// screenshots/documents/extremely-unusable photos never reach here in the first place, so
    /// "favorite screenshot never forced-selected" (§ 55) falls out for free.
    private static func preferredCandidate(_ a: DuplicateCandidate, _ b: DuplicateCandidate, config: Configuration) -> DuplicateCandidate {
        switch (a.isFavorite, b.isFavorite) {
        case (true, false):
            return (b.compositeScore - a.compositeScore) > config.favoriteSignificantlyWorseMargin ? b : a
        case (false, true):
            return (a.compositeScore - b.compositeScore) > config.favoriteSignificantlyWorseMargin ? a : b
        default:
            if a.compositeScore != b.compositeScore { return a.compositeScore > b.compositeScore ? a : b }
            return a.assetID < b.assetID ? a : b
        }
    }

    /// Picks the `limit` most-preferred photos out of `photos` (already all "selected" —
    /// duplicates/quality losers are never passed in), one round of `preferredCandidate` at a
    /// time. `limit` is always small (`momentAutoSelectRatio`-derived, typically single digits),
    /// so this is cheap.
    private static func topCandidates(_ photos: [AnalyzedPhoto], limit: Int, config: Configuration) -> [AnalyzedPhoto] {
        guard limit > 0, !photos.isEmpty else { return [] }
        var remaining = photos
        var kept: [AnalyzedPhoto] = []

        while kept.count < limit, !remaining.isEmpty {
            let winner = remaining.dropFirst().reduce(remaining[0]) { current, candidate in
                let a = DuplicateCandidate(assetID: current.assetID, compositeScore: current.metrics.compositeScore, isFavorite: current.metrics.isFavorite)
                let b = DuplicateCandidate(assetID: candidate.assetID, compositeScore: candidate.metrics.compositeScore, isFavorite: candidate.metrics.isFavorite)
                return preferredCandidate(a, b, config: config).assetID == a.assetID ? current : candidate
            }
            kept.append(winner)
            remaining.removeAll { $0.assetID == winner.assetID }
        }
        return kept
    }

    // MARK: - Quality Gate (§ 18-22)

    /// A hard usability floor, checked before any ranking happens. Never consults `faceScore`
    /// (§ 20) — a landscape/no-person photo is fully valid. A Favorite gets its own, lower floor
    /// (§ 22): moderately blurred/underexposed still passes, but Favorite does not override
    /// screenshot/document exclusion, nor does it rescue a genuinely broken image.
    private static func rejectionReason(for photo: AnalyzedPhoto, config: Configuration) -> CurationRejectionReason? {
        if photo.isScreenshot { return .screenshot }
        if photo.isDocument { return .document }
        let sharpnessFloor = photo.metrics.isFavorite ? config.minimumUsableSharpnessForFavorite : config.minimumUsableSharpness
        let exposureFloor = photo.metrics.isFavorite ? config.minimumUsableExposureForFavorite : config.minimumUsableExposure
        if photo.metrics.sharpness < sharpnessFloor || photo.metrics.exposure < exposureFloor { return .lowQuality }
        return nil
    }

    // MARK: - Per-cluster selection (§ 12, § 13; Quality Gate § 18-22; Favorite § 33-36)

    private static func selectWithinGroup(photos: [AnalyzedPhoto], config: Configuration) -> [PhotoCurationItem] {
        let clusters = Dictionary(grouping: photos, by: \.similarityClusterID)
        var selectedIDs = Set<String>()
        var reasonByAssetID: [String: CurationRejectionReason] = [:]

        for photo in photos {
            if let reason = rejectionReason(for: photo, config: config) {
                reasonByAssetID[photo.assetID] = reason
            }
        }

        for clusterPhotos in clusters.values {
            // Screenshots, document-style photos, and anything failing the Quality Gate are never
            // ranking-eligible — see docs/sprint/SPRINT-005B-TODO.md item 7 and
            // SPRINT-SMART-EVENT-HIGHLIGHTS.md § 18-22. If a whole cluster is made of nothing
            // else, it simply contributes no selection; every photo still shows up (unselected)
            // in the grid, and the user can always select one manually.
            let eligible = clusterPhotos.filter { reasonByAssetID[$0.assetID] == nil }
            guard !eligible.isEmpty else { continue }

            let ranked = eligible.sorted { $0.metrics.compositeScore > $1.metrics.compositeScore }
            let topOverall = ranked[0]
            let topFavorite = ranked.first { $0.metrics.isFavorite }
            let best: AnalyzedPhoto = {
                guard let topFavorite, topFavorite.assetID != topOverall.assetID else { return topOverall }
                let a = DuplicateCandidate(assetID: topOverall.assetID, compositeScore: topOverall.metrics.compositeScore, isFavorite: topOverall.metrics.isFavorite)
                let b = DuplicateCandidate(assetID: topFavorite.assetID, compositeScore: topFavorite.metrics.compositeScore, isFavorite: topFavorite.metrics.isFavorite)
                return preferredCandidate(a, b, config: config).assetID == a.assetID ? topOverall : topFavorite
            }()

            guard best.metrics.compositeScore >= config.lowQualityFloor else {
                reasonByAssetID[best.assetID] = .lowQuality
                continue
            }

            var clusterSelected: Set<String> = [best.assetID]

            if ranked.count > config.largeBurstSize, let runnerUp = ranked.first(where: { $0.assetID != best.assetID }) {
                let scoreClose = abs(best.metrics.compositeScore - runnerUp.metrics.compositeScore) <= config.largeBurstRunnerUpScoreMargin
                let farEnoughApart = abs(runnerUp.creationDate.timeIntervalSince(best.creationDate)) >= config.largeBurstRunnerUpMinTimeGapSeconds
                if scoreClose, farEnoughApart, runnerUp.metrics.compositeScore >= config.lowQualityFloor {
                    clusterSelected.insert(runnerUp.assetID)
                }
            }

            selectedIDs.formUnion(clusterSelected)
            for candidate in eligible where !clusterSelected.contains(candidate.assetID) {
                reasonByAssetID[candidate.assetID] = .nearDuplicate
            }
        }

        // Cap total auto-selected within this one moment at `momentAutoSelectRatio` of the
        // moment's own photo count (minimum 1), regardless of how many distinct near-duplicate
        // clusters contributed a winner above — see `Configuration.momentAutoSelectRatio`. Ranked
        // with the same Favorite-aware comparator duplicate resolution uses, so "N best" means the
        // same thing here as it does when resolving a duplicate cluster.
        let momentCap = max(1, Int((Double(photos.count) * config.momentAutoSelectRatio).rounded()))
        if selectedIDs.count > momentCap {
            let selectedPhotos = photos.filter { selectedIDs.contains($0.assetID) }
            let kept = Set(topCandidates(selectedPhotos, limit: momentCap, config: config).map(\.assetID))
            for photo in selectedPhotos where !kept.contains(photo.assetID) {
                selectedIDs.remove(photo.assetID)
                reasonByAssetID[photo.assetID] = .trimmed
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
                selectionSource: .systemSuggested,
                rejectionReason: isSelected ? nil : reasonByAssetID[photo.assetID]
            )
        }
    }

    // MARK: - Global duplicate suppression (§ 27-32)

    /// Collapses locally-selected representatives that a global visual pass judges to be
    /// duplicates of each other — same subject/pose/background, even across different sessions or
    /// more than a moment apart. Only items already `isSelected` participate; losers are
    /// unselected and stamped `.globalDuplicate`, resolved via the same Favorite-aware comparator
    /// local selection uses (§ 32's priority: explicit user choice is handled separately/
    /// unconditionally by `applyPreservedUserOverrides`, so this only needs Favorite > quality >
    /// deterministic tie-break).
    private static func applyGlobalDuplicateSuppression(
        groups: inout [PhotoCurationGroup],
        analyzedPhotosByAssetID: [String: AnalyzedPhoto],
        globalDuplicateGroups: [String: String],
        config: Configuration
    ) {
        guard !globalDuplicateGroups.isEmpty else { return }

        struct Ref: Equatable {
            let groupIndex: Int
            let itemIndex: Int
        }

        var refsByGlobalGroup: [String: [Ref]] = [:]
        for (groupIndex, group) in groups.enumerated() {
            for (itemIndex, item) in group.items.enumerated() where item.isSelected {
                guard let globalGroupID = globalDuplicateGroups[item.assetID] else { continue }
                refsByGlobalGroup[globalGroupID, default: []].append(Ref(groupIndex: groupIndex, itemIndex: itemIndex))
            }
        }

        for refs in refsByGlobalGroup.values where refs.count > 1 {
            let candidates: [(ref: Ref, candidate: DuplicateCandidate)] = refs.map { ref in
                let item = groups[ref.groupIndex].items[ref.itemIndex]
                let isFavorite = analyzedPhotosByAssetID[item.assetID]?.metrics.isFavorite ?? false
                return (ref, DuplicateCandidate(assetID: item.assetID, compositeScore: Double(item.qualityScore) / 100, isFavorite: isFavorite))
            }

            let winner = candidates.dropFirst().reduce(candidates[0]) { current, next in
                preferredCandidate(current.candidate, next.candidate, config: config).assetID == current.candidate.assetID ? current : next
            }

            for entry in candidates where entry.ref != winner.ref {
                groups[entry.ref.groupIndex].items[entry.ref.itemIndex].isSelected = false
                groups[entry.ref.groupIndex].items[entry.ref.itemIndex].rejectionReason = .globalDuplicate
            }
        }
    }

    // MARK: - Event-level balancing + lightweight temporal diversity (§ 14; § 37-40, § 56)

    static func targetRange(forSourceAssetCount count: Int) -> ClosedRange<Int> {
        switch count {
        case ..<50: 8...20
        case 50..<150: 15...30
        case 150..<300: 20...40
        default: 30...60
        }
    }

    private static func temporalBucketKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    /// Large Events (matching `targetRange`'s own top bracket) get a genuinely enforced ceiling —
    /// see the second pass below. Smaller Events keep the original soft/floor-protected behavior.
    private static let hardCapMinimumSourceAssetCount = 300

    /// A light touch: never force-adds when under the reference range (§ 14 explicitly says not
    /// to pad a selection just to hit a number), only trims when well past it. The last remaining
    /// selected item in a moment-group is never trimmed by the first pass (absolute floor,
    /// existing behavior) — but see the second pass below for large Events.
    ///
    /// Trimming does NOT simply "sort everything by score, remove the lowest" (§ 39 explicitly
    /// warns against exactly that) — a naive global sort would drain a lower-scoring minority day
    /// (e.g. Day 2/3 of a multi-day Event) before touching a dominant, higher-scoring Day 1, even
    /// though Day 1 has far more slack to give up. Instead, each removal comes from whichever
    /// calendar-day bucket currently holds the *most* selected photos (§ 37-38) — within that
    /// bucket, non-favorites are cut before favorites (§ 36), then lowest quality score first.
    /// This naturally protects sparse days: they only start losing photos once every other day's
    /// bucket has been reduced down to the same size.
    private static func balanceAcrossEvent(
        groups: inout [PhotoCurationGroup],
        analyzedPhotosByAssetID: [String: AnalyzedPhoto],
        sourceAssetCount: Int,
        config: Configuration
    ) {
        let range = targetRange(forSourceAssetCount: sourceAssetCount)
        let ceiling = Int(Double(range.upperBound) * config.overSelectionCeilingMultiplier)
        var totalSelected = groups.reduce(0) { $0 + $1.suggestedCount }
        guard totalSelected > ceiling else { return }

        struct Ref {
            let groupIndex: Int
            let itemIndex: Int
            let score: Int
            let isFavorite: Bool
            let bucketKey: String
        }

        var refs: [Ref] = []
        for (groupIndex, group) in groups.enumerated() {
            let bucketKey = temporalBucketKey(for: group.startDate)
            for (itemIndex, item) in group.items.enumerated() where item.isSelected {
                let isFavorite = analyzedPhotosByAssetID[item.assetID]?.metrics.isFavorite ?? false
                refs.append(Ref(groupIndex: groupIndex, itemIndex: itemIndex, score: item.qualityScore, isFavorite: isFavorite, bucketKey: bucketKey))
            }
        }

        var bucketCounts: [String: Int] = [:]
        for ref in refs { bucketCounts[ref.bucketKey, default: 0] += 1 }

        // `respectFloor: true` never empties a moment-group (existing guarantee); `false` allows
        // it — used only by the large-Event escalation pass below, when the floor itself is the
        // reason the ceiling can't be reached (many small moments, each protected at 1, whose sum
        // alone already exceeds the target — the exact failure mode behind a ~500-photo Event
        // landing at ~400 selected: no per-moment cap existed then either, see
        // `Configuration.momentAutoSelectRatio`).
        func runTrim(target: Int, respectFloor: Bool) {
            func isRemovable(_ ref: Ref) -> Bool { !respectFloor || groups[ref.groupIndex].suggestedCount > 1 }

            while totalSelected > target {
                let candidateBucketKeys = Set(refs.filter { bucketCounts[$0.bucketKey, default: 0] > 0 && isRemovable($0) }.map(\.bucketKey))
                guard let targetBucket = candidateBucketKeys
                    .compactMap({ key in bucketCounts[key].map { (key, $0) } })
                    .max(by: { $0.1 < $1.1 })?.0
                else { break }

                let candidates = refs.filter { $0.bucketKey == targetBucket && groups[$0.groupIndex].items[$0.itemIndex].isSelected && isRemovable($0) }
                guard let victim = candidates.min(by: { lhs, rhs in
                    if lhs.isFavorite != rhs.isFavorite { return !lhs.isFavorite }
                    return lhs.score < rhs.score
                }) else { break }

                groups[victim.groupIndex].items[victim.itemIndex].isSelected = false
                groups[victim.groupIndex].items[victim.itemIndex].rejectionReason = .trimmed
                totalSelected -= 1
                bucketCounts[targetBucket, default: 0] -= 1
            }
        }

        runTrim(target: ceiling, respectFloor: true)

        guard totalSelected > ceiling, sourceAssetCount >= Self.hardCapMinimumSourceAssetCount else { return }
        // The floor-respecting pass above couldn't even reach the soft ceiling — meaning the
        // Event has more moment-groups than the ceiling allows, each protected at its floor of 1.
        // For a large Event, honor the real target (`range.upperBound`) instead of leaving an
        // arbitrarily large count on the table; a moment-group may now be fully emptied if that's
        // the only way there, using the same largest-bucket/favorite-last/lowest-score ordering.
        runTrim(target: range.upperBound, respectFloor: false)
    }
}
