//
//  EventDiscoveryEngineTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation
import Testing
@testable import Nizi

struct EventDiscoveryEngineTests {
    private static let reference = ISO8601DateFormatter().date(from: "2024-06-08T08:00:00Z")!

    private func makeAsset(
        id: String,
        daysFromReference: Double = 0,
        hoursFromReference: Double = 0,
        minutesFromReference: Double = 0,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isFavorite: Bool = false,
        isScreenshot: Bool = false,
        burstIdentifier: String? = nil,
        mediaType: PhotoMediaType = .image
    ) -> IndexedAsset {
        let date = Self.reference.addingTimeInterval(
            daysFromReference * 86400 + hoursFromReference * 3600 + minutesFromReference * 60
        )
        return IndexedAsset(
            id: id,
            creationDate: date,
            latitude: latitude,
            longitude: longitude,
            isFavorite: isFavorite,
            isScreenshot: isScreenshot,
            burstIdentifier: burstIdentifier,
            mediaType: mediaType
        )
    }

    /// 4-day trip, 6 shooting blocks/day, 4 photos each — all within a tight geo radius.
    private func tripFixture() -> [IndexedAsset] {
        var assets: [IndexedAsset] = []
        for day in 0..<4 {
            for hour in stride(from: 8, to: 20, by: 2) {
                for i in 0..<4 {
                    assets.append(makeAsset(
                        id: "trip-\(day)-\(hour)-\(i)",
                        daysFromReference: Double(day),
                        hoursFromReference: Double(hour),
                        minutesFromReference: Double(i) * 10,
                        latitude: 16.0544 + Double(i) * 0.001,
                        longitude: 108.2022 + Double(i) * 0.001,
                        isFavorite: i == 0
                    ))
                }
            }
        }
        return assets
    }

    @Test func sameFixtureProducesDeterministicResult() {
        let assets = tripFixture()
        let now = Date()

        let first = EventDiscoveryEngine.discover(from: assets, now: now)
        let second = EventDiscoveryEngine.discover(from: assets, now: now)

        #expect(first.events.count == second.events.count)
        let firstSignature = first.events.map { ($0.assetIDs.sorted(), $0.score, $0.titleSuggestion, $0.eventType) }
        let secondSignature = second.events.map { ($0.assetIDs.sorted(), $0.score, $0.titleSuggestion, $0.eventType) }
        #expect(firstSignature.elementsEqual(secondSignature) {
            $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 && $0.3 == $1.3
        })
    }

    @Test func eventHasScoreAndReasons() throws {
        let result = EventDiscoveryEngine.discover(from: tripFixture())

        let event = try #require(result.events.first)
        #expect(event.score > 0 && event.score <= 1)
        #expect(!event.discoveryReasons.isEmpty)
        #expect(event.eventType == .trip)
    }

    @Test func assetsWithoutGPSStillClusterByTime() throws {
        var assets: [IndexedAsset] = []
        for i in 0..<15 {
            assets.append(makeAsset(id: "nogps-\(i)", minutesFromReference: Double(i) * 10))
        }

        let result = EventDiscoveryEngine.discover(from: assets)

        let event = try #require(result.events.first)
        #expect(result.events.count == 1)
        #expect(event.assetIDs.count == assets.count)
    }

    @Test func screenshotOnlyClusterProducesNoEvent() {
        var assets: [IndexedAsset] = []
        for i in 0..<15 {
            assets.append(makeAsset(id: "shot-\(i)", minutesFromReference: Double(i) * 10, isScreenshot: true))
        }

        let result = EventDiscoveryEngine.discover(from: assets)

        #expect(result.events.isEmpty)
    }

    @Test func tooFewPlainAssetsProduceNoEvent() {
        let assets = (0..<3).map { makeAsset(id: "few-\($0)", minutesFromReference: Double($0) * 10) }

        let result = EventDiscoveryEngine.discover(from: assets)

        #expect(result.events.isEmpty)
    }

    @Test func favoritesLowerTheMinimumEventSize() throws {
        // 8 assets: below the 12-photo default minimum, but above the 6-photo
        // reduced minimum that applies once favorites are present.
        var assets: [IndexedAsset] = []
        for i in 0..<8 {
            assets.append(makeAsset(id: "fav-\(i)", minutesFromReference: Double(i) * 10, isFavorite: i == 0))
        }

        let result = EventDiscoveryEngine.discover(from: assets)

        let event = try #require(result.events.first)
        #expect(event.assetIDs.count == 8)
    }

    @Test func discoverFoldsInFastEventQualityForEveryEvent() throws {
        // Confirms the SPRINT-FAST-EVENT-QUALITY wiring end-to-end (not just the isolated
        // `FastEventQualityService`) — `discover(...)` must return events already carrying
        // plausible quality fields, not the struct's bare defaults.
        let result = EventDiscoveryEngine.discover(from: tripFixture())

        let event = try #require(result.events.first)
        #expect(event.eventQualityScore > 0)
        #expect(event.eventQualityScore <= 1)
    }

    // MARK: - Home Source Unification (SPRINT-NEXT § 1-4)

    /// 10 weekly evening visits at one coordinate — enough distinct days/return visits for
    /// `LocationIntelligenceEngine.detectHome` to win a real (if low-confidence) `HomeAnchor`.
    private func recurringHomeFixture(latitude: Double, longitude: Double) -> [IndexedAsset] {
        var assets: [IndexedAsset] = []
        for week in 0..<10 {
            for photoIndex in 0..<2 {
                assets.append(makeAsset(
                    id: "recurring-\(week)-\(photoIndex)",
                    daysFromReference: Double(week * 7), hoursFromReference: 19 + Double(photoIndex) * 0.1,
                    latitude: latitude, longitude: longitude
                ))
            }
        }
        return assets
    }

    @Test func userConfirmedPreferredHomeWinsOverFreshlyComputedHome() throws {
        let assets = recurringHomeFixture(latitude: 21.0285, longitude: 105.8542)
        let confirmed = HomeAnchor(
            clusterID: UUID(), centerLatitude: 10.7626, centerLongitude: 106.6602,
            homeScore: 0.9, confidence: .high, source: .userConfirmed
        )

        let result = EventDiscoveryEngine.discover(from: assets, preferredHome: confirmed)

        #expect(result.home == confirmed)
    }

    @Test func noConfirmedHomeUsesFreshlyComputedHomeOverStaleInferred() throws {
        let assets = recurringHomeFixture(latitude: 21.0285, longitude: 105.8542)
        let staleInferred = HomeAnchor(
            clusterID: UUID(), centerLatitude: 10.7626, centerLongitude: 106.6602,
            homeScore: 0.5, confidence: .low, source: .inferred
        )

        let result = EventDiscoveryEngine.discover(from: assets, preferredHome: staleInferred)

        let home = try #require(result.home)
        #expect(home.source == .inferred)
        #expect(abs(home.centerLatitude - 21.0285) < 0.1)
    }

    @Test func fallsBackToStaleInferredHomeWhenFreshComputationFindsNothing() {
        // No GPS on any asset at all — LocationIntelligenceEngine.analyze finds zero located
        // assets and returns `home: nil` before detectHome ever runs.
        let assets = (0..<5).map { makeAsset(id: "nogps-\($0)", minutesFromReference: Double($0) * 10) }
        let staleInferred = HomeAnchor(
            clusterID: UUID(), centerLatitude: 10.7626, centerLongitude: 106.6602,
            homeScore: 0.5, confidence: .low, source: .inferred
        )

        let result = EventDiscoveryEngine.discover(from: assets, preferredHome: staleInferred)

        #expect(result.home == staleInferred)
    }

    @Test func distinctSessionsFarApartInTimeAndSpaceStayAsSeparateEvents() {
        var assets: [IndexedAsset] = []
        for i in 0..<12 {
            assets.append(makeAsset(
                id: "hanoi-\(i)",
                daysFromReference: 0,
                minutesFromReference: Double(i) * 10,
                latitude: 21.0285,
                longitude: 105.8542
            ))
        }
        for i in 0..<12 {
            assets.append(makeAsset(
                id: "saigon-\(i)",
                daysFromReference: 60,
                minutesFromReference: Double(i) * 10,
                latitude: 10.7626,
                longitude: 106.6602
            ))
        }

        let result = EventDiscoveryEngine.discover(from: assets)

        #expect(result.events.count == 2)
    }
}
