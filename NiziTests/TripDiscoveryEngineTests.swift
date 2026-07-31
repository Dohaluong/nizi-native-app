//
//  TripDiscoveryEngineTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation
import Testing
@testable import Nizi

struct TripDiscoveryEngineTests {
    private static let reference = ISO8601DateFormatter().date(from: "2024-06-08T08:00:00Z")!
    private static let home = HomeAnchor(clusterID: UUID(), centerLatitude: 21.0285, centerLongitude: 105.8542, homeScore: 0.9, confidence: .high)

    private func makeEventWithSession(startOffsetDays: Double, durationHours: Double, latitude: Double, longitude: Double) -> (event: PhotoEvent, session: PhotoSession) {
        let start = Self.reference.addingTimeInterval(startOffsetDays * 86400)
        let end = start.addingTimeInterval(durationHours * 3600)
        let sessionID = UUID()
        let session = PhotoSession(
            id: sessionID, startDate: start, endDate: end,
            centerLatitude: latitude, centerLongitude: longitude,
            geoCell: EventDiscoveryEngine.geoCell(latitude: latitude, longitude: longitude),
            assetIDs: ["a1", "a2"], densityScore: 2
        )
        let event = PhotoEvent(
            id: UUID(), titleSuggestion: "Event", startDate: start, endDate: end,
            primaryLocationLabel: nil, eventType: .dayEvent, score: 0.8, status: .new,
            sessionIDs: [sessionID], assetIDs: ["a1", "a2"], coverAssetID: "a1",
            discoveryReasons: [], algorithmVersion: 1, createdAt: start, updatedAt: start
        )
        return (event, session)
    }

    /// Fixture A — a normal local day (Home → cafe → restaurant → Home) produces no Trip.
    @Test func allLocalDayProducesNoTrip() {
        let (event1, session1) = makeEventWithSession(startOffsetDays: 0, durationHours: 2, latitude: 21.031, longitude: 105.860)
        let (event2, session2) = makeEventWithSession(startOffsetDays: 1, durationHours: 2, latitude: 21.028, longitude: 105.855)

        let trips = DefaultTripDiscoveryEngine().detectTrips(
            events: [event1, event2], sessions: [session1, session2], home: Self.home, config: .default
        )

        #expect(trips.isEmpty)
    }

    /// Fixture B — Hanoi → Da Nang → Hoi An → Da Nang → Hanoi groups into one Trip with
    /// multiple Events, not one giant Event.
    @Test func domesticMultiCitySequenceGroupsIntoOneTrip() {
        let (event1, session1) = makeEventWithSession(startOffsetDays: 10, durationHours: 6, latitude: 16.0544, longitude: 108.2022)
        let (event2, session2) = makeEventWithSession(startOffsetDays: 11, durationHours: 6, latitude: 15.8801, longitude: 108.3380)
        let (event3, session3) = makeEventWithSession(startOffsetDays: 12, durationHours: 6, latitude: 16.0544, longitude: 108.2022)

        let trips = DefaultTripDiscoveryEngine().detectTrips(
            events: [event1, event2, event3], sessions: [session1, session2, session3], home: Self.home, config: .default
        )

        #expect(trips.count == 1)
        #expect(trips.first?.eventIDs.count == 3)
    }

    /// Fixture F — AC-08: a large jump between cities within a trip (Tokyo → 450km → Kyoto) may
    /// split at the Event level, but must not automatically split the Trip.
    @Test func largeDistanceBetweenCitiesStaysOneTrip() {
        let (tokyoEvent, tokyoSession) = makeEventWithSession(startOffsetDays: 20, durationHours: 6, latitude: 35.6762, longitude: 139.6503)
        let (kyotoEvent, kyotoSession) = makeEventWithSession(startOffsetDays: 21, durationHours: 6, latitude: 35.0116, longitude: 135.7681)

        let trips = DefaultTripDiscoveryEngine().detectTrips(
            events: [tokyoEvent, kyotoEvent], sessions: [tokyoSession, kyotoSession], home: Self.home, config: .default
        )

        #expect(trips.count == 1)
        #expect(trips.first?.eventIDs.count == 2)
    }

    @Test func noHomeProducesNoTrips() {
        let (event1, session1) = makeEventWithSession(startOffsetDays: 10, durationHours: 6, latitude: 16.0544, longitude: 108.2022)

        let trips = DefaultTripDiscoveryEngine().detectTrips(events: [event1], sessions: [session1], home: nil, config: .default)

        #expect(trips.isEmpty)
    }
}
