//
//  MemoryPotentialEvaluatorTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation
import Testing
@testable import Nizi

struct MemoryPotentialEvaluatorTests {
    private static let reference = ISO8601DateFormatter().date(from: "2024-06-08T08:00:00Z")!
    private static let home = HomeAnchor(clusterID: UUID(), centerLatitude: 21.0285, centerLongitude: 105.8542, homeScore: 0.9, confidence: .high)

    private func makeAsset(id: String, isFavorite: Bool = false, latitude: Double? = nil, longitude: Double? = nil) -> IndexedAsset {
        IndexedAsset(
            id: id, creationDate: Self.reference, latitude: latitude, longitude: longitude,
            isFavorite: isFavorite, isScreenshot: false, burstIdentifier: nil, mediaType: .image
        )
    }

    private func makeEvent(
        durationMinutes: Double,
        assetIDs: [String],
        sessionCount: Int = 1,
        eventQualityScore: Double = 0.9,
        eventVisibility: EventVisibility = .normal
    ) -> PhotoEvent {
        var event = PhotoEvent(
            id: UUID(), titleSuggestion: "Test Event", startDate: Self.reference,
            endDate: Self.reference.addingTimeInterval(durationMinutes * 60),
            primaryLocationLabel: nil, eventType: .dayEvent, score: 0.5, status: .new,
            sessionIDs: (0..<sessionCount).map { _ in UUID() }, assetIDs: assetIDs, coverAssetID: assetIDs.first,
            discoveryReasons: [], algorithmVersion: 1, createdAt: Self.reference, updatedAt: Self.reference
        )
        event.eventQualityScore = eventQualityScore
        event.eventVisibility = eventVisibility
        return event
    }

    private func makeTrip(eventID: UUID, classification: TravelClassification, overnightCount: Int) -> PhotoTrip {
        PhotoTrip(
            id: UUID(), startDate: Self.reference, endDate: Self.reference,
            eventIDs: [eventID], primaryLatitude: nil, primaryLongitude: nil,
            primaryCountryCode: nil, primaryPlaceName: nil, classification: classification, confidence: 0.8,
            travelContext: TravelContext(
                homeCountryCode: nil, maxDistanceFromHomeKm: 500, overnightCount: overnightCount,
                countryCodes: [], hasDepartureFromHome: true, hasReturnToHome: true
            )
        )
    }

    private func evaluate(event: PhotoEvent, assets: [IndexedAsset], trips: [PhotoTrip] = []) -> MemoryPotentialEvaluator.Result {
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let results = MemoryPotentialEvaluator.evaluate(
            events: [event], trips: trips, assetsByID: assetsByID,
            home: Self.home, familiarPlaces: [], config: .default
        )
        return results[0]
    }

    @Test func hiddenNoiseEventNeverBecomesAutoMemoryEvenWithStrongSignals() {
        let assets = (0..<10).map { makeAsset(id: "a-\($0)", isFavorite: true) }
        let event = makeEvent(
            durationMinutes: 600, assetIDs: assets.map(\.id), sessionCount: 5,
            eventQualityScore: 0.9, eventVisibility: .hiddenNoise
        )

        let result = evaluate(event: event, assets: assets)

        #expect(!result.trace.isAutoMemory)
        #expect(!result.event.isAutoMemory)
    }

    @Test func belowQualityThresholdEventNeverBecomesAutoMemory() {
        let assets = (0..<10).map { makeAsset(id: "a-\($0)", isFavorite: true) }
        let event = makeEvent(
            durationMinutes: 600, assetIDs: assets.map(\.id), sessionCount: 5,
            eventQualityScore: EventDiscoveryConfig.default.memoryPotentialQualityThreshold - 0.01,
            eventVisibility: .normal
        )

        let result = evaluate(event: event, assets: assets)

        #expect(!result.trace.isAutoMemory)
    }

    /// Doc's own example (SPRINT-NEXT § 13): "Quality cao, 6 ảnh ở nhà, 10 phút, 0 favorite" must
    /// not become an Auto Memory — no strong signal fires at all.
    @Test func homeExampleFromSpecDoesNotBecomeAutoMemory() {
        let assets = (0..<6).map { makeAsset(id: "h-\($0)", latitude: Self.home.centerLatitude, longitude: Self.home.centerLongitude) }
        let event = makeEvent(durationMinutes: 10, assetIDs: assets.map(\.id), sessionCount: 1)

        let result = evaluate(event: event, assets: assets)

        #expect(!result.trace.isAutoMemory)
    }

    /// Doc's own example (SPRINT-NEXT § 13): "Quality tốt, 3 ngày ở Đà Nẵng, away, 8 Favorite" must
    /// become an Auto Memory.
    @Test func daNangExampleFromSpecBecomesAutoMemory() {
        let assets = (0..<20).map { makeAsset(id: "dn-\($0)", isFavorite: $0 < 8, latitude: 16.0544, longitude: 108.2022) }
        let event = makeEvent(durationMinutes: 3 * 24 * 60, assetIDs: assets.map(\.id), sessionCount: 6)
        let trip = makeTrip(eventID: event.id, classification: .domesticTrip, overnightCount: 2)

        let result = evaluate(event: event, assets: assets, trips: [trip])

        #expect(result.trace.isAutoMemory)
        #expect(result.event.isAutoMemory)
    }

    @Test func internationalTripMembershipAloneIsSufficientStrongSignal() {
        let assets = (0..<10).map { makeAsset(id: "i-\($0)", latitude: Self.home.centerLatitude, longitude: Self.home.centerLongitude) }
        let event = makeEvent(durationMinutes: 60, assetIDs: assets.map(\.id))
        let trip = makeTrip(eventID: event.id, classification: .internationalTrip, overnightCount: 0)

        let result = evaluate(event: event, assets: assets, trips: [trip])

        #expect(result.trace.isAutoMemory)
        #expect(result.trace.reasons.first { $0.name == "International Trip" }?.isMet == true)
    }

    @Test func highFavoriteRatioAloneIsSufficientStrongSignal() {
        // 3 of 4 assets favorited (75%) clears memoryPotentialMinimumFavoriteRatio(0.2) even
        // though the raw favorite count (3) is under memoryPotentialMinimumFavoriteCount(5).
        let assets = (0..<4).map { makeAsset(id: "r-\($0)", isFavorite: $0 < 3, latitude: Self.home.centerLatitude, longitude: Self.home.centerLongitude) }
        let event = makeEvent(durationMinutes: 60, assetIDs: assets.map(\.id))

        let result = evaluate(event: event, assets: assets)

        #expect(result.trace.isAutoMemory)
        #expect(result.trace.reasons.first { $0.name == "Favorite Ratio" }?.isMet == true)
        #expect(result.trace.reasons.first { $0.name == "Favorite Count" }?.isMet == false)
    }

    @Test func photoCountAloneCanBeTheStrongSignalButNeverTheBaseGate() {
        let manyAssets = (0..<70).map { makeAsset(id: "p-\($0)", latitude: Self.home.centerLatitude, longitude: Self.home.centerLongitude) }
        let normalQualityEvent = makeEvent(durationMinutes: 60, assetIDs: manyAssets.map(\.id), eventQualityScore: 0.9)
        let lowQualityEvent = makeEvent(durationMinutes: 60, assetIDs: manyAssets.map(\.id), eventQualityScore: 0.4)

        let qualifies = evaluate(event: normalQualityEvent, assets: manyAssets)
        let stillGated = evaluate(event: lowQualityEvent, assets: manyAssets)

        #expect(qualifies.trace.isAutoMemory)
        #expect(!stillGated.trace.isAutoMemory)
    }

    /// Documents SPRINT-NEXT § 14's conservativeness intent structurally: several unremarkable,
    /// ordinary Events (decent quality, but no strong signal) all stay `false`.
    @Test func mostOrdinaryEventsRemainNotAutoMemory() {
        let fixtures: [(assetCount: Int, favoriteCount: Int, durationMinutes: Double, sessionCount: Int)] = [
            (8, 0, 45, 1),
            (15, 1, 90, 2),
            (5, 0, 20, 1),
            (12, 0, 120, 2)
        ]

        for fixture in fixtures {
            let assets = (0..<fixture.assetCount).map {
                makeAsset(id: "o-\($0)", isFavorite: $0 < fixture.favoriteCount, latitude: Self.home.centerLatitude, longitude: Self.home.centerLongitude)
            }
            let event = makeEvent(durationMinutes: fixture.durationMinutes, assetIDs: assets.map(\.id), sessionCount: fixture.sessionCount)

            let result = evaluate(event: event, assets: assets)

            #expect(!result.trace.isAutoMemory)
        }
    }
}
