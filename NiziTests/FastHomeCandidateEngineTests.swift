//
//  FastHomeCandidateEngineTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation
import Testing
@testable import Nizi

struct FastHomeCandidateEngineTests {
    private static let reference = ISO8601DateFormatter().date(from: "2020-01-01T08:00:00Z")!

    private func makeRecord(id: String, monthsFromReference: Int, dayOffset: Double, latitude: Double, longitude: Double) -> PhotoAssetRecord {
        let monthDate = Calendar.current.date(byAdding: .month, value: monthsFromReference, to: Self.reference) ?? Self.reference
        let date = monthDate.addingTimeInterval(dayOffset * 86400)
        return PhotoAssetRecord(
            id: id, creationDate: date, modificationDate: date, mediaType: .image,
            pixelWidth: 100, pixelHeight: 100, duration: 0, latitude: latitude, longitude: longitude,
            isFavorite: false, isHidden: false, isScreenshot: false, burstIdentifier: nil, sourceType: .userLibrary
        )
    }

    /// The Fixture-H shape: a lightly-photographed, long-term recurring place must beat a
    /// photo-heavy short trip, even though the trip alone produces far more raw photos.
    @Test func homeWinsOverPhotoHeavyShortTrip() throws {
        var accumulator = FastHomeObservationAccumulator(maxPerMonth: 15)

        let homeRecords = (0..<24).map { month in
            makeRecord(id: "home-\(month)", monthsFromReference: month, dayOffset: 1, latitude: 21.0285, longitude: 105.8542)
        }
        accumulator.add(records: homeRecords)

        // 500 photos crammed into a single month, far away — the per-month sampling cap keeps
        // this from drowning out two years of home life.
        let vacationRecords = (0..<500).map { index in
            makeRecord(id: "trip-\(index)", monthsFromReference: 12, dayOffset: Double(index) * 0.01, latitude: 16.0544, longitude: 108.2022)
        }
        accumulator.add(records: vacationRecords)

        let candidates = DefaultFastHomeCandidateDetector().candidates(from: accumulator.allObservations, config: .default)

        let winner = try #require(candidates.first)
        #expect(abs(winner.centerLatitude - 21.0285) < 0.1)
    }

    @Test func notReadyWithSparseData() {
        var accumulator = FastHomeObservationAccumulator()
        accumulator.add(records: [makeRecord(id: "a", monthsFromReference: 0, dayOffset: 0, latitude: 21.03, longitude: 105.85)])

        let candidates = DefaultFastHomeCandidateDetector().candidates(from: accumulator.allObservations, config: .default)

        #expect(!FastHomeCandidateReadiness.isReady(candidates: candidates, config: .default))
    }

    @Test func readyWithOneStrongLongTermCandidate() {
        var accumulator = FastHomeObservationAccumulator()
        let records = (0..<36).map { month in
            makeRecord(id: "home-\(month)", monthsFromReference: month, dayOffset: 1, latitude: 21.03, longitude: 105.85)
        }
        accumulator.add(records: records)

        let candidates = DefaultFastHomeCandidateDetector().candidates(from: accumulator.allObservations, config: .default)

        #expect(FastHomeCandidateReadiness.isReady(candidates: candidates, config: .default))
    }

    @Test func noObservationsProducesNoCandidates() {
        let candidates = DefaultFastHomeCandidateDetector().candidates(from: [], config: .default)
        #expect(candidates.isEmpty)
    }
}
