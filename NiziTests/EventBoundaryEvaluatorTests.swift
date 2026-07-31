//
//  EventBoundaryEvaluatorTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation
import Testing
@testable import Nizi

struct EventBoundaryEvaluatorTests {
    private static let reference = ISO8601DateFormatter().date(from: "2024-06-08T08:00:00Z")!

    private func makeSession(
        startOffsetHours: Double,
        durationHours: Double,
        latitude: Double?,
        longitude: Double?,
        assetCount: Int = 10
    ) -> PhotoSession {
        let start = Self.reference.addingTimeInterval(startOffsetHours * 3600)
        let end = start.addingTimeInterval(durationHours * 3600)
        let cell: String? = if let latitude, let longitude {
            EventDiscoveryEngine.geoCell(latitude: latitude, longitude: longitude)
        } else {
            nil
        }
        return PhotoSession(
            id: UUID(), startDate: start, endDate: end,
            centerLatitude: latitude, centerLongitude: longitude, geoCell: cell,
            assetIDs: (0..<assetCount).map { "asset-\($0)" },
            densityScore: Double(assetCount) / max(durationHours, 1.0 / 60)
        )
    }

    private func context(durationHours: Double = 0, home: HomeAnchor? = nil) -> EventBoundaryContext {
        EventBoundaryContext(home: home, familiarPlaces: [], currentEventDurationHours: durationHours, currentEventSessionCount: 1)
    }

    /// Fixture D — a real Event (conference) followed by a 40h gap then unrelated family photos
    /// in a different city; must not be glued onto the conference's tail.
    @Test func unrelatedTailIsSplit() {
        let conference = makeSession(startOffsetHours: 44, durationHours: 4, latitude: 21.0285, longitude: 105.8542)
        let familyPhotos = makeSession(startOffsetHours: 44 + 4 + 40, durationHours: 2, latitude: 10.7626, longitude: 106.6602)

        let decision = DefaultEventBoundaryEvaluator().evaluate(
            previous: conference, next: familyPhotos, context: context(durationHours: 44)
        )

        #expect(decision.action == .split)
    }

    /// Fixture E — a long, sparse, unrelated chain must not collapse into one multi-day Event.
    @Test func longSparseUnrelatedChainIsSplit() {
        let day1 = makeSession(startOffsetHours: 0, durationHours: 1, latitude: 21.0, longitude: 105.8, assetCount: 3)
        let day2 = makeSession(startOffsetHours: 30, durationHours: 1, latitude: 10.0, longitude: 108.0, assetCount: 2)

        let decision = DefaultEventBoundaryEvaluator().evaluate(previous: day1, next: day2, context: context())

        #expect(decision.action == .split)
    }

    @Test func hardBoundaryFiresOnLargeGapJumpAndReturnHome() {
        let home = HomeAnchor(clusterID: UUID(), centerLatitude: 21.0285, centerLongitude: 105.8542, homeScore: 0.9, confidence: .high)
        let away = makeSession(startOffsetHours: 0, durationHours: 4, latitude: 16.0544, longitude: 108.2022)
        let backHome = makeSession(startOffsetHours: 4 + 18, durationHours: 2, latitude: 21.0285, longitude: 105.8542)

        let decision = DefaultEventBoundaryEvaluator().evaluate(
            previous: away, next: backHome, context: context(durationHours: 4, home: home)
        )

        #expect(decision.isHardBoundary)
        #expect(decision.action == .split)
    }

    /// SPEC § 35 — missing GPS must not block a clustering decision the time signal alone supports.
    @Test func missingGPSStillMergesOnTightTimeGap() {
        let first = makeSession(startOffsetHours: 0, durationHours: 0.5, latitude: nil, longitude: nil)
        let second = makeSession(startOffsetHours: 0.7, durationHours: 0.5, latitude: nil, longitude: nil)

        let decision = DefaultEventBoundaryEvaluator().evaluate(previous: first, next: second, context: context())

        #expect(decision.action == .merge)
    }
}
