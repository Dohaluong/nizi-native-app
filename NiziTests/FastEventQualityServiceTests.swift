//
//  FastEventQualityServiceTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation
import Testing
@testable import Nizi

struct FastEventQualityServiceTests {
    private static let reference = ISO8601DateFormatter().date(from: "2024-06-08T08:00:00Z")!

    private func makeAsset(
        id: String,
        minutesFromReference: Double,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isFavorite: Bool = false,
        isScreenshot: Bool = false
    ) -> IndexedAsset {
        IndexedAsset(
            id: id,
            creationDate: Self.reference.addingTimeInterval(minutesFromReference * 60),
            latitude: latitude,
            longitude: longitude,
            isFavorite: isFavorite,
            isScreenshot: isScreenshot,
            burstIdentifier: nil,
            mediaType: .image
        )
    }

    private func makeEvent(
        startDate: Date,
        endDate: Date,
        assetIDs: [String],
        sessionIDs: [UUID] = [UUID()]
    ) -> PhotoEvent {
        PhotoEvent(
            id: UUID(),
            titleSuggestion: "Test Event",
            startDate: startDate,
            endDate: endDate,
            primaryLocationLabel: nil,
            eventType: .dayEvent,
            score: 0.5,
            status: .new,
            sessionIDs: sessionIDs,
            assetIDs: assetIDs,
            coverAssetID: assetIDs.first,
            discoveryReasons: [],
            algorithmVersion: 1,
            createdAt: startDate,
            updatedAt: startDate
        )
    }

    private func classify(
        event: PhotoEvent,
        assets: [IndexedAsset],
        trips: [PhotoTrip] = [],
        home: HomeAnchor? = nil,
        familiarPlaces: [FamiliarPlace] = []
    ) -> FastEventQualityService.Result {
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let results = FastEventQualityService.classify(
            events: [event], assetsByID: assetsByID, trips: trips,
            home: home, familiarPlaces: familiarPlaces, config: .default
        )
        return results[0]
    }

    private func reason(_ result: FastEventQualityService.Result, named name: String) -> EventQualitySignalResult? {
        result.trace.reasons.first { $0.name == name }
    }

    // 10 assets, 10 min apart (many distinct moments), one session, no screenshots, no GPS,
    // >1h duration, no trip — a clean baseline every other test tweaks one signal on top of.
    private func baselineAssets(favoriteCount: Int = 0, screenshotCount: Int = 0) -> [IndexedAsset] {
        (0..<10).map { index in
            makeAsset(
                id: "a-\(index)", minutesFromReference: Double(index) * 10,
                isFavorite: index < favoriteCount, isScreenshot: index < screenshotCount
            )
        }
    }

    @Test func favoritePresenceIncreasesScore() {
        let withoutFavorite = baselineAssets()
        let withFavorite = baselineAssets(favoriteCount: 1)
        let event = makeEvent(startDate: Self.reference, endDate: Self.reference.addingTimeInterval(100 * 60), assetIDs: withoutFavorite.map(\.id))

        let resultA = classify(event: event, assets: withoutFavorite)
        let resultB = classify(event: event, assets: withFavorite)

        #expect(reason(resultA, named: "Favorite")?.contribution == 0)
        #expect(reason(resultB, named: "Favorite")?.contribution == 0.20)
        #expect(resultB.trace.score > resultA.trace.score)
    }

    @Test func mostlyScreenshotsStronglyPenalized() {
        let noScreenshots = baselineAssets()
        let mostlyScreenshots = baselineAssets(screenshotCount: 8)
        let event = makeEvent(startDate: Self.reference, endDate: Self.reference.addingTimeInterval(100 * 60), assetIDs: noScreenshots.map(\.id))

        let resultA = classify(event: event, assets: noScreenshots)
        let resultB = classify(event: event, assets: mostlyScreenshots)

        #expect(reason(resultA, named: "Screenshot Ratio")?.contribution == 0)
        #expect(reason(resultB, named: "Screenshot Ratio")?.contribution == -0.30)
        #expect(resultB.trace.score < resultA.trace.score)
    }

    @Test func missingGPSIsNeutralNotPenalized() {
        let assets = baselineAssets()
        let event = makeEvent(startDate: Self.reference, endDate: Self.reference.addingTimeInterval(100 * 60), assetIDs: assets.map(\.id))

        let result = classify(event: event, assets: assets)

        // No GPS on any asset — must contribute exactly 0, never a negative penalty (§10).
        #expect(reason(result, named: "GPS")?.contribution == 0)
    }

    @Test func gpsPresenceContributesASmallBonus() {
        let assets = (0..<10).map { index in
            makeAsset(id: "g-\(index)", minutesFromReference: Double(index) * 10, latitude: 10.0, longitude: 10.0)
        }
        let event = makeEvent(startDate: Self.reference, endDate: Self.reference.addingTimeInterval(100 * 60), assetIDs: assets.map(\.id))

        let result = classify(event: event, assets: assets)

        #expect(reason(result, named: "GPS")?.contribution == 0.05)
    }

    @Test func homeContextOnlyPenalizesWhenLowSignalAndAtHome() {
        let home = HomeAnchor(clusterID: UUID(), centerLatitude: 10.0, centerLongitude: 10.0, homeScore: 0.9, confidence: .high)

        // Case A: few assets, short duration, at Home — expect the penalty.
        let lowSignalAssets = (0..<3).map { index in
            makeAsset(id: "h-\(index)", minutesFromReference: Double(index), latitude: 10.0, longitude: 10.0)
        }
        let lowSignalEvent = makeEvent(
            startDate: Self.reference, endDate: Self.reference.addingTimeInterval(10 * 60), assetIDs: lowSignalAssets.map(\.id)
        )
        let lowSignalResult = classify(event: lowSignalEvent, assets: lowSignalAssets, home: home)
        #expect(reason(lowSignalResult, named: "Home Context")?.contribution == -0.10)

        // Case B: many assets, longer duration, still at Home — no penalty ("Sinh nhật ở nhà vẫn
        // là Event tốt").
        let goodAssets = (0..<10).map { index in
            makeAsset(id: "hg-\(index)", minutesFromReference: Double(index) * 10, latitude: 10.0, longitude: 10.0)
        }
        let goodEvent = makeEvent(
            startDate: Self.reference, endDate: Self.reference.addingTimeInterval(100 * 60), assetIDs: goodAssets.map(\.id)
        )
        let goodResult = classify(event: goodEvent, assets: goodAssets, home: home)
        #expect(reason(goodResult, named: "Home Context")?.contribution == 0)
    }

    @Test func tripMembershipAndMultiDayBonusStack() {
        let assets = baselineAssets()
        let event = makeEvent(startDate: Self.reference, endDate: Self.reference.addingTimeInterval(100 * 60), assetIDs: assets.map(\.id))

        func trip(overnightCount: Int) -> PhotoTrip {
            PhotoTrip(
                id: UUID(), startDate: Self.reference, endDate: Self.reference,
                eventIDs: [event.id], primaryLatitude: nil, primaryLongitude: nil,
                primaryCountryCode: nil, primaryPlaceName: nil, classification: .unknown, confidence: 0.5,
                travelContext: TravelContext(
                    homeCountryCode: nil, maxDistanceFromHomeKm: nil, overnightCount: overnightCount,
                    countryCodes: [], hasDepartureFromHome: false, hasReturnToHome: false
                )
            )
        }

        let noTrip = classify(event: event, assets: assets, trips: [])
        let dayTrip = classify(event: event, assets: assets, trips: [trip(overnightCount: 0)])
        let multiDayTrip = classify(event: event, assets: assets, trips: [trip(overnightCount: 1)])

        #expect(reason(noTrip, named: "Trip")?.contribution == 0)
        #expect(reason(dayTrip, named: "Trip")?.contribution == 0.12)
        #expect(reason(multiDayTrip, named: "Trip")?.contribution == 0.20)
    }

    @Test func photoCountNeverHardRejects() {
        // Only 3 photos — below the "low asset count" threshold — but favorite + GPS + a
        // multi-day trip more than make up for it. Must still land `.normal`, proving there is
        // no hard `photoCount < X → hide` cutoff (§13).
        let assets = [
            makeAsset(id: "p-0", minutesFromReference: 0, latitude: 10.0, longitude: 10.0, isFavorite: true),
            makeAsset(id: "p-1", minutesFromReference: 20, latitude: 10.0, longitude: 10.0),
            makeAsset(id: "p-2", minutesFromReference: 40, latitude: 10.0, longitude: 10.0)
        ]
        let event = makeEvent(startDate: Self.reference, endDate: Self.reference.addingTimeInterval(90 * 60), assetIDs: assets.map(\.id))
        let trip = PhotoTrip(
            id: UUID(), startDate: Self.reference, endDate: Self.reference,
            eventIDs: [event.id], primaryLatitude: nil, primaryLongitude: nil,
            primaryCountryCode: nil, primaryPlaceName: nil, classification: .unknown, confidence: 0.5,
            travelContext: TravelContext(
                homeCountryCode: nil, maxDistanceFromHomeKm: nil, overnightCount: 2,
                countryCodes: [], hasDepartureFromHome: false, hasReturnToHome: false
            )
        )

        let result = classify(event: event, assets: assets, trips: [trip])

        #expect(assets.count < EventDiscoveryConfig.default.eventQualityLowAssetCountThreshold)
        #expect(result.trace.visibility == .normal)
    }

    @Test func threeTierVisibilityCutoffsRespectConfigThresholds() {
        let config = EventDiscoveryConfig.default

        // (a) strong on every signal → .normal
        let greatAssets = (0..<20).map { index in
            makeAsset(id: "great-\(index)", minutesFromReference: Double(index) * 10, latitude: 10.0, longitude: 10.0, isFavorite: index == 0)
        }
        let greatEvent = makeEvent(
            startDate: Self.reference, endDate: Self.reference.addingTimeInterval(200 * 60),
            assetIDs: greatAssets.map(\.id), sessionIDs: [UUID(), UUID(), UUID()]
        )
        let greatTrip = PhotoTrip(
            id: UUID(), startDate: Self.reference, endDate: Self.reference, eventIDs: [greatEvent.id],
            primaryLatitude: nil, primaryLongitude: nil, primaryCountryCode: nil, primaryPlaceName: nil,
            classification: .unknown, confidence: 0.5,
            travelContext: TravelContext(homeCountryCode: nil, maxDistanceFromHomeKm: nil, overnightCount: 2, countryCodes: [], hasDepartureFromHome: false, hasReturnToHome: false)
        )
        let greatResult = classify(event: greatEvent, assets: greatAssets, trips: [greatTrip])
        #expect(greatResult.trace.score >= config.eventQualityNormalThreshold)
        #expect(greatResult.trace.visibility == .normal)

        // (b) one asset-count penalty + one duration penalty, nothing else → .lowValue.
        // Assets are spaced 10 min apart (> the 5 min moment-gap threshold) specifically so this
        // does NOT also trip the single-moment penalty — isolating exactly two signals.
        let mediumAssets = (0..<3).map { index in makeAsset(id: "medium-\(index)", minutesFromReference: Double(index) * 10) }
        let mediumEvent = makeEvent(startDate: Self.reference, endDate: Self.reference.addingTimeInterval(20 * 60), assetIDs: mediumAssets.map(\.id))
        let mediumResult = classify(event: mediumEvent, assets: mediumAssets)
        #expect(mediumResult.trace.score >= config.eventQualityLowValueThreshold)
        #expect(mediumResult.trace.score < config.eventQualityNormalThreshold)
        #expect(mediumResult.trace.visibility == .lowValue)

        // (c) every penalty stacked (few photos, single moment, mostly screenshots, short
        // duration, low-signal at Home) → .hiddenNoise
        let home = HomeAnchor(clusterID: UUID(), centerLatitude: 10.0, centerLongitude: 10.0, homeScore: 0.9, confidence: .high)
        let badAssets = (0..<3).map { index in
            makeAsset(id: "bad-\(index)", minutesFromReference: Double(index), latitude: 10.0, longitude: 10.0, isScreenshot: true)
        }
        let badEvent = makeEvent(startDate: Self.reference, endDate: Self.reference.addingTimeInterval(2 * 60), assetIDs: badAssets.map(\.id))
        let badResult = classify(event: badEvent, assets: badAssets, home: home)
        #expect(badResult.trace.score < config.eventQualityLowValueThreshold)
        #expect(badResult.trace.visibility == .hiddenNoise)
    }
}
