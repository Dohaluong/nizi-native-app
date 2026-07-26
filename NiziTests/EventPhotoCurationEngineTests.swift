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
            algorithmVersion: 1
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
            algorithmVersion: 1
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
}
