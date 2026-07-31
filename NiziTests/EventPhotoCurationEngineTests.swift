//
//  EventPhotoCurationEngineTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation
import Testing
@testable import Nizi

struct EventPhotoCurationEngineTests {
    private static let reference = ISO8601DateFormatter().date(from: "2024-06-08T08:00:00Z")!
    private let sessionID = UUID()

    /// There is no required final photo count by default (`enforceEventWideCeiling == false`) —
    /// only tests that specifically exercise `balanceAcrossEvent`'s trimming need to opt back in.
    private var enforcingCeiling: EventPhotoCurationEngine.Configuration {
        var config = EventPhotoCurationEngine.Configuration.default
        config.enforceEventWideCeiling = true
        return config
    }

    private func photo(
        id: String,
        minutesFromReference: Double,
        clusterID: String,
        sharpness: Double = 0.8,
        exposure: Double = 0.8,
        faceScore: Double = 0.5,
        isFavorite: Bool = false
    ) -> AnalyzedPhoto {
        AnalyzedPhoto(
            assetID: id,
            sessionID: sessionID,
            creationDate: Self.reference.addingTimeInterval(minutesFromReference * 60),
            metrics: PhotoQualityMetrics(sharpness: sharpness, exposure: exposure, faceScore: faceScore, isFavorite: isFavorite),
            similarityClusterID: clusterID
        )
    }

    @Test func distinctSingletonsAreAllSelected() {
        let photos = [
            photo(id: "a", minutesFromReference: 0, clusterID: "a"),
            photo(id: "b", minutesFromReference: 10, clusterID: "b"),
            photo(id: "c", minutesFromReference: 20, clusterID: "c")
        ]

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: photos,
            photoEventID: UUID(),
            sourceAssetCount: photos.count,
            algorithmVersion: 1
        )

        #expect(result.selectedAssetCount == 3)
    }

    @Test func smallNearDuplicateClusterPicksOnlyTheBest() {
        let photos = (0..<5).map { index in
            photo(
                id: "dup-\(index)",
                minutesFromReference: Double(index),
                clusterID: "burst",
                sharpness: index == 2 ? 0.95 : 0.5
            )
        }

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: photos,
            photoEventID: UUID(),
            sourceAssetCount: photos.count,
            algorithmVersion: 1
        )

        #expect(result.selectedAssetCount == 1)
        #expect(result.orderedSelectedAssetIdentifiers == ["dup-2"])
    }

    @Test func largeBurstMayPickARunnerUpWhenFarApartAndCloseInScore() {
        // 8 photos, same cluster; two of them (index 0 and 6) are strong and far apart in time.
        // 30s between shots (not 2 minutes) — must stay within `momentGroupMaxGapSeconds` (60s)
        // consecutive-gap so all 8 land in the same displayed group, matching how a real burst's
        // `similarityClusterID` is only ever formed from consecutive gaps that tight in the first
        // place (`VisionEventPhotoAnalyzer.Configuration.nearDuplicateMaxTimeGapSeconds`).
        let photos = (0..<8).map { index in
            photo(
                id: "burst-\(index)",
                minutesFromReference: Double(index) * 0.5,
                clusterID: "large-burst",
                sharpness: (index == 0 || index == 6) ? 0.9 : 0.4
            )
        }

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: photos,
            photoEventID: UUID(),
            sourceAssetCount: photos.count,
            algorithmVersion: 1
        )

        #expect(result.selectedAssetCount == 2)
        #expect(Set(result.orderedSelectedAssetIdentifiers) == ["burst-0", "burst-6"])
    }

    @Test func lowQualityClusterSelectsNothing() {
        let photos = (0..<4).map { index in
            photo(id: "bad-\(index)", minutesFromReference: Double(index), clusterID: "bad", sharpness: 0.05, exposure: 0.05)
        }

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: photos,
            photoEventID: UUID(),
            sourceAssetCount: photos.count,
            algorithmVersion: 1
        )

        #expect(result.selectedAssetCount == 0)
    }

    @Test func balancingNeverEmptiesAGroupThatOnlyHasOneSelection() {
        // 40 distinct singleton clusters, each its own session, each clearing the quality floor.
        // These are 40 genuinely distinct moments, not near-duplicates of each other — trimming
        // any of them to zero would silently erase a whole moment from the timeline, which § 14
        // explicitly warns against ("không bỏ trống các phần quan trọng trong timeline"). So even
        // though 40 exceeds the sub-50-asset ceiling (30), nothing here is safe to cut.
        var photos: [AnalyzedPhoto] = []
        for index in 0..<40 {
            photos.append(AnalyzedPhoto(
                assetID: "solo-\(index)",
                sessionID: UUID(),
                creationDate: Self.reference.addingTimeInterval(Double(index) * 86400),
                metrics: PhotoQualityMetrics(sharpness: 0.8, exposure: 0.8, faceScore: 0.5, isFavorite: false),
                similarityClusterID: "solo-\(index)"
            ))
        }

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: photos,
            photoEventID: UUID(),
            sourceAssetCount: photos.count,
            algorithmVersion: 1,
            config: enforcingCeiling
        )

        #expect(result.selectedAssetCount == 40)
        #expect(result.groups.allSatisfy { $0.suggestedCount == 1 })
    }

    @Test func balancingTrimsWeakestItemsFirstWhenGroupsHaveSlack() {
        // 20 sessions, each an 8-photo burst with two strong, well-separated shots (indices 0
        // and 6) — the large-burst runner-up rule picks both, so every group starts with 2
        // selected. `sourceAssetCount` is passed independently of the synthetic photo count to
        // force the strictest bucket (< 50 → ceiling 30), so the 40 initial selections must trim.
        // 30s between shots (not 120s) — must stay under `momentGroupMaxGapSeconds` (60s) so all
        // 8 stay one displayed group; this test is about balancing/trimming, not moment-splitting.
        var photos: [AnalyzedPhoto] = []
        for group in 0..<20 {
            let groupSessionID = UUID()
            for index in 0..<8 {
                photos.append(AnalyzedPhoto(
                    assetID: "g\(group)-\(index)",
                    sessionID: groupSessionID,
                    creationDate: Self.reference.addingTimeInterval(Double(group) * 86400 + Double(index) * 30),
                    metrics: PhotoQualityMetrics(
                        sharpness: (index == 0 || index == 6) ? 0.9 : 0.3,
                        exposure: 0.8,
                        faceScore: 0.5,
                        isFavorite: false
                    ),
                    similarityClusterID: "cluster-\(group)"
                ))
            }
        }

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: photos,
            photoEventID: UUID(),
            sourceAssetCount: 10,
            algorithmVersion: 1,
            config: enforcingCeiling
        )

        #expect(result.selectedAssetCount <= 30)
        #expect(result.groups.count == 20)
        #expect(result.groups.allSatisfy { $0.suggestedCount >= 1 })
    }

    @Test func sameInputProducesDeterministicSelection() {
        let photos = [
            photo(id: "a", minutesFromReference: 0, clusterID: "a", isFavorite: true),
            photo(id: "b", minutesFromReference: 5, clusterID: "b")
        ]

        let first = EventPhotoCurationEngine.curate(
            analyzedPhotos: photos, photoEventID: UUID(), sourceAssetCount: photos.count, algorithmVersion: 1
        )
        let second = EventPhotoCurationEngine.curate(
            analyzedPhotos: photos, photoEventID: UUID(), sourceAssetCount: photos.count, algorithmVersion: 1
        )

        #expect(first.orderedSelectedAssetIdentifiers == second.orderedSelectedAssetIdentifiers)
        #expect(first.selectedAssetCount == second.selectedAssetCount)
    }

    @Test func sourceAssetCountAndStatusAreSetOnTheResult() {
        let photos = [photo(id: "a", minutesFromReference: 0, clusterID: "a")]
        let eventID = UUID()

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: photos,
            photoEventID: eventID,
            sourceAssetCount: photos.count,
            algorithmVersion: 3
        )

        #expect(result.photoEventID == eventID)
        #expect(result.sourceAssetCount == 1)
        #expect(result.algorithmVersion == 3)
        #expect(result.status == .completed)
    }

    // MARK: - Quality Gate (SPRINT-SMART-EVENT-HIGHLIGHTS.md § 18-22)

    @Test func severelyBlurredPhotoNotAutoSelectedButStillPresent() {
        let photos = [photo(id: "a", minutesFromReference: 0, clusterID: "a", sharpness: 0.02, exposure: 0.8)]

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: photos, photoEventID: UUID(), sourceAssetCount: photos.count, algorithmVersion: 1
        )

        #expect(result.selectedAssetCount == 0)
        let allItems = result.groups.flatMap(\.items)
        #expect(allItems.count == 1)
        #expect(allItems.first?.rejectionReason == .lowQuality)
    }

    @Test func favoriteScreenshotNeverAutoSelected() {
        let screenshot = AnalyzedPhoto(
            assetID: "shot", sessionID: sessionID, creationDate: Self.reference,
            metrics: PhotoQualityMetrics(sharpness: 0.9, exposure: 0.9, faceScore: 0.9, isFavorite: true),
            similarityClusterID: "shot", isScreenshot: true
        )

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: [screenshot], photoEventID: UUID(), sourceAssetCount: 1, algorithmVersion: 1
        )

        #expect(result.selectedAssetCount == 0)
        #expect(result.groups.flatMap(\.items).first?.rejectionReason == .screenshot)
    }

    @Test func favoriteExtremelyUnusableNeverForcedSelected() {
        let photos = [photo(id: "a", minutesFromReference: 0, clusterID: "a", sharpness: 0.01, exposure: 0.01, isFavorite: true)]

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: photos, photoEventID: UUID(), sourceAssetCount: photos.count, algorithmVersion: 1
        )

        #expect(result.selectedAssetCount == 0)
        #expect(result.groups.flatMap(\.items).first?.rejectionReason == .lowQuality)
    }

    // MARK: - Favorite priority (§ 33-36)

    @Test func favoriteWinsWithinAcceptableQualityMargin() {
        // nonFavorite composite = 0.35 + 0.25 + 0.25 = 0.85; favorite composite ≈ 0.755 (gap ≈
        // 0.095, inside the default 0.15 margin) — the Favorite should win the cluster.
        let nonFavorite = photo(id: "non-fav", minutesFromReference: 0, clusterID: "c", sharpness: 1.0, exposure: 1.0, faceScore: 1.0)
        let favorite = photo(id: "fav", minutesFromReference: 0.2, clusterID: "c", sharpness: 0.8, exposure: 0.8, faceScore: 0.5, isFavorite: true)

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: [nonFavorite, favorite], photoEventID: UUID(), sourceAssetCount: 2, algorithmVersion: 1
        )

        #expect(result.orderedSelectedAssetIdentifiers == ["fav"])
        #expect(result.groups.flatMap(\.items).first { $0.assetID == "non-fav" }?.rejectionReason == .nearDuplicate)
    }

    @Test func favoriteLosesWhenSignificantlyWorse() {
        // nonFavorite composite = 0.85; favorite composite ≈ 0.32 (gap ≈ 0.53, well past the
        // default 0.15 margin) — the non-favorite should win despite the other candidate being Favorite.
        let nonFavorite = photo(id: "non-fav", minutesFromReference: 0, clusterID: "c", sharpness: 1.0, exposure: 1.0, faceScore: 1.0)
        let favorite = photo(id: "fav", minutesFromReference: 0.2, clusterID: "c", sharpness: 0.2, exposure: 0.2, faceScore: 0.2, isFavorite: true)

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: [nonFavorite, favorite], photoEventID: UUID(), sourceAssetCount: 2, algorithmVersion: 1
        )

        #expect(result.orderedSelectedAssetIdentifiers == ["non-fav"])
        #expect(result.groups.flatMap(\.items).first { $0.assetID == "fav" }?.rejectionReason == .nearDuplicate)
    }

    // MARK: - Global duplicate suppression (§ 27-32)

    @Test func crossClusterDuplicatesResolvedByGlobalPassOnly() {
        // Two distinct, non-adjacent singleton clusters — locally each is its own auto-selected
        // representative. A hand-built `globalDuplicateGroups` map simulates the global visual
        // pass judging them duplicates of each other despite never having been locally clustered.
        let a = photo(id: "a", minutesFromReference: 0, clusterID: "a")
        let b = photo(id: "b", minutesFromReference: 30, clusterID: "b")

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: [a, b], photoEventID: UUID(), sourceAssetCount: 2,
            algorithmVersion: 1, globalDuplicateGroups: ["a": "g1", "b": "g1"]
        )

        #expect(result.selectedAssetCount == 1)
        #expect(result.groups.flatMap(\.items).count == 2)
        let loser = result.groups.flatMap(\.items).first { !$0.isSelected }
        #expect(loser?.rejectionReason == .globalDuplicate)
    }

    // MARK: - Lightweight temporal diversity (§ 37-40, § 56)

    @Test func temporalDiversityProtectsMinorityDaysFromTrim() {
        let dayBase = Calendar.current.startOfDay(for: Self.reference)

        func burst(dayOffset: Double, sessionOffsetSeconds: Double, clusterID: String, strongSharpness: Double, weakSharpness: Double) -> [AnalyzedPhoto] {
            let sessionStart = dayBase.addingTimeInterval(dayOffset * 86400 + sessionOffsetSeconds)
            let burstSessionID = UUID()
            return (0..<8).map { index in
                AnalyzedPhoto(
                    assetID: "\(clusterID)-\(index)",
                    sessionID: burstSessionID,
                    creationDate: sessionStart.addingTimeInterval(Double(index) * 30),
                    metrics: PhotoQualityMetrics(
                        sharpness: (index == 0 || index == 6) ? strongSharpness : weakSharpness,
                        exposure: 0.8, faceScore: 0.5, isFavorite: false
                    ),
                    similarityClusterID: clusterID
                )
            }
        }

        var photos: [AnalyzedPhoto] = []
        // Day 1: 20 sessions sharing one calendar day, high quality — lots of trimmable slack.
        for session in 0..<20 {
            photos += burst(dayOffset: 0, sessionOffsetSeconds: Double(session) * 60, clusterID: "day1-\(session)", strongSharpness: 0.9, weakSharpness: 0.3)
        }
        // Day 2 and Day 3: one session each, lower quality but usable — minority days.
        photos += burst(dayOffset: 1, sessionOffsetSeconds: 0, clusterID: "day2", strongSharpness: 0.5, weakSharpness: 0.2)
        photos += burst(dayOffset: 2, sessionOffsetSeconds: 0, clusterID: "day3", strongSharpness: 0.5, weakSharpness: 0.2)

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: photos, photoEventID: UUID(), sourceAssetCount: 10, algorithmVersion: 1,
            config: enforcingCeiling
        )

        func suggestedCount(forClusterPrefix prefix: String) -> Int {
            result.groups.first { $0.items.contains { $0.assetID.hasPrefix(prefix) } }?.suggestedCount ?? -1
        }

        #expect(result.selectedAssetCount <= 30)
        #expect(suggestedCount(forClusterPrefix: "day2") == 2)
        #expect(suggestedCount(forClusterPrefix: "day3") == 2)
    }

    // MARK: - Event-wide ceiling is opt-in (no required final photo count by default)

    private func manySingletonMoments(count: Int) -> [AnalyzedPhoto] {
        (0..<count).map { index in
            AnalyzedPhoto(
                assetID: "solo-\(index)",
                sessionID: UUID(),
                creationDate: Self.reference.addingTimeInterval(Double(index) * 60),
                metrics: PhotoQualityMetrics(sharpness: 0.8, exposure: 0.8, faceScore: 0.5, isFavorite: false),
                similarityClusterID: "solo-\(index)"
            )
        }
    }

    @Test func eventWideCeilingOffByDefaultDoesNotLimitFinalCount() {
        let photos = manySingletonMoments(count: 100)

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: photos, photoEventID: UUID(), sourceAssetCount: 300, algorithmVersion: 1
            // default config — `enforceEventWideCeiling` is false, so all 100 stand.
        )

        #expect(result.selectedAssetCount == 100)
    }

    @Test func hardCeilingEscalatesPastMomentFloorForLargeEventsWhenOptedIn() {
        // 100 genuinely distinct singleton moments — the floor-respecting pass alone can't trim
        // any of them (each is already at its floor of 1), which is exactly the failure mode
        // behind a real ~500-photo Event landing at ~400 selected. For an Event this large
        // (≥300), opting into `enforceEventWideCeiling` must still reach the real target even if
        // that means emptying some moments entirely.
        let photos = manySingletonMoments(count: 100)

        let result = EventPhotoCurationEngine.curate(
            analyzedPhotos: photos, photoEventID: UUID(), sourceAssetCount: 300, algorithmVersion: 1,
            config: enforcingCeiling
        )

        #expect(result.selectedAssetCount == EventPhotoCurationEngine.targetRange(forSourceAssetCount: 300).upperBound)
    }

    // MARK: - Preserving manual selection (§ 5-8)

    @Test func captureAndApplyUserOverridesForcesUserChoiceOverTheAlgorithm() {
        let eventID = UUID()
        let staleResult = EventCurationResult.fixtureForOverrideTests(
            photoEventID: eventID,
            items: [
                ("kept-by-user", true, .userAdded),
                ("removed-by-user", false, .userRemoved),
                ("untouched", true, .systemSuggested)
            ]
        )
        let overrides = EventPhotoCurationEngine.captureUserOverrides(from: staleResult)

        // A brand-new algorithm run that disagrees with the user on every overridden asset —
        // the freshest run still has "removed-by-user" marked selected and "kept-by-user"
        // marked unselected, simulating the algorithm changing its mind after a recurate.
        let freshResult = EventCurationResult.fixtureForOverrideTests(
            photoEventID: eventID,
            items: [
                ("kept-by-user", false, .systemSuggested),
                ("removed-by-user", true, .systemSuggested),
                ("untouched", true, .systemSuggested)
            ]
        )

        let merged = EventPhotoCurationEngine.applyPreservedUserOverrides(to: freshResult, overrides: overrides)
        let itemsByAssetID = Dictionary(uniqueKeysWithValues: merged.groups.flatMap(\.items).map { ($0.assetID, $0) })

        #expect(itemsByAssetID["kept-by-user"]?.isSelected == true)
        #expect(itemsByAssetID["kept-by-user"]?.selectionSource == .userAdded)
        #expect(itemsByAssetID["removed-by-user"]?.isSelected == false)
        #expect(itemsByAssetID["removed-by-user"]?.selectionSource == .userRemoved)
        // Untouched by the user — the fresh algorithm's own call stands.
        #expect(itemsByAssetID["untouched"]?.isSelected == true)
        #expect(itemsByAssetID["untouched"]?.selectionSource == .systemSuggested)
    }

    @Test func applyPreservedUserOverridesSkipsAssetsNoLongerInTheEvent() {
        let eventID = UUID()
        let staleResult = EventCurationResult.fixtureForOverrideTests(
            photoEventID: eventID,
            items: [("gone-from-event", true, .userAdded)]
        )
        let overrides = EventPhotoCurationEngine.captureUserOverrides(from: staleResult)

        let freshResult = EventCurationResult.fixtureForOverrideTests(
            photoEventID: eventID,
            items: [("still-here", true, .systemSuggested)]
        )

        let merged = EventPhotoCurationEngine.applyPreservedUserOverrides(to: freshResult, overrides: overrides)

        // No orphan item created for the asset that left the Event — the merged result only
        // ever contains items the fresh algorithm run actually produced.
        #expect(merged.groups.flatMap(\.items).map(\.assetID) == ["still-here"])
    }
}

private extension EventCurationResult {
    /// Minimal fixture for `UserOverrideSnapshot` tests — one flat group, `isSelected`/
    /// `selectionSource` set directly per item, everything else defaulted.
    static func fixtureForOverrideTests(photoEventID: UUID, items: [(assetID: String, isSelected: Bool, source: SelectionSource)]) -> EventCurationResult {
        let now = Date()
        let curationItems = items.enumerated().map { index, entry in
            PhotoCurationItem(
                id: UUID(), assetID: entry.assetID, sortOrder: index, qualityScore: 50,
                similarityClusterID: entry.assetID, isSuggested: entry.isSelected,
                isSelected: entry.isSelected, selectionSource: entry.source
            )
        }
        let group = PhotoCurationGroup(id: UUID(), sessionID: nil, startDate: now, endDate: now, sortOrder: 0, items: curationItems)
        return EventCurationResult(
            photoEventID: photoEventID, status: .completed, algorithmVersion: 1,
            createdAt: now, updatedAt: now, completedAt: now,
            sourceAssetCount: items.count, errorMessage: nil, groups: [group]
        )
    }
}
