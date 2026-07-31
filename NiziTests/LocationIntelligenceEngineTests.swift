//
//  LocationIntelligenceEngineTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation
import Testing
@testable import Nizi

struct LocationIntelligenceEngineTests {
    private static let reference = ISO8601DateFormatter().date(from: "2023-01-01T08:00:00Z")!

    private func makeAsset(id: String, daysFromReference: Double, hoursFromReference: Double, latitude: Double, longitude: Double) -> IndexedAsset {
        let date = Self.reference.addingTimeInterval(daysFromReference * 86400 + hoursFromReference * 3600)
        return IndexedAsset(
            id: id, creationDate: date, latitude: latitude, longitude: longitude,
            isFavorite: false, isScreenshot: false, burstIdentifier: nil, mediaType: .image
        )
    }

    /// ~18 months of weekly evening visits, 4 photos each — a realistic recurring Home.
    private func homeFixture() -> [IndexedAsset] {
        var assets: [IndexedAsset] = []
        for week in 0..<78 {
            for photoIndex in 0..<4 {
                assets.append(makeAsset(
                    id: "home-\(week)-\(photoIndex)",
                    daysFromReference: Double(week * 7),
                    hoursFromReference: 19 + Double(photoIndex) * 0.1,
                    latitude: 21.0285, longitude: 105.8542
                ))
            }
        }
        return assets
    }

    /// 5 consecutive days, 400 photos/day, far away — a photo-heavy vacation that must not
    /// outscore Home despite ~2000 photos vs. Home's ~300.
    private func vacationFixture() -> [IndexedAsset] {
        var assets: [IndexedAsset] = []
        for day in 0..<5 {
            for photoIndex in 0..<400 {
                assets.append(makeAsset(
                    id: "vacation-\(day)-\(photoIndex)",
                    daysFromReference: 400 + Double(day),
                    hoursFromReference: 8 + Double(photoIndex) * (10.0 / 400.0),
                    latitude: 16.0544, longitude: 108.2022
                ))
            }
        }
        return assets
    }

    @Test func homeWinsOverPhotoHeavyVacationDespiteFewerPhotos() throws {
        let assets = homeFixture() + vacationFixture()
        let result = LocationIntelligenceEngine.analyze(from: assets)

        let home = try #require(result.home)
        #expect(abs(home.centerLatitude - 21.0285) < 0.1)

        let homeCluster = try #require(result.clusters.first { $0.id == home.clusterID })
        let vacationCluster = try #require(result.clusters.first { $0.id != home.clusterID })

        #expect(homeCluster.assetCount < vacationCluster.assetCount)
        #expect(LocationIntelligenceEngine.homeScore(for: homeCluster) > LocationIntelligenceEngine.homeScore(for: vacationCluster))
    }

    @Test func tooLittleHistoryProducesNoHome() {
        var assets: [IndexedAsset] = []
        for day in 0..<3 {
            assets.append(makeAsset(id: "short-\(day)", daysFromReference: Double(day), hoursFromReference: 19, latitude: 21.0285, longitude: 105.8542))
        }
        let result = LocationIntelligenceEngine.analyze(from: assets)
        #expect(result.home == nil)
    }

    @Test func recurringButNonDominantClusterBecomesFamiliarNotHome() throws {
        var officeAssets: [IndexedAsset] = []
        for week in 0..<20 {
            officeAssets.append(makeAsset(
                id: "office-\(week)", daysFromReference: Double(week * 7) + 1, hoursFromReference: 9,
                latitude: 21.05, longitude: 105.80
            ))
        }
        let assets = homeFixture() + officeAssets
        let result = LocationIntelligenceEngine.analyze(from: assets)

        let home = try #require(result.home)
        #expect(abs(home.centerLatitude - 21.0285) < 0.01)
        #expect(result.familiarPlaces.contains { $0.clusterID != home.clusterID })
    }
}
