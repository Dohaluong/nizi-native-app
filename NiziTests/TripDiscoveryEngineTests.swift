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
            events: [event1, event2], sessions: [session1, session2], home: Self.home, familiarPlaces: [], config: .default
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
            events: [event1, event2, event3], sessions: [session1, session2, session3], home: Self.home, familiarPlaces: [], config: .default
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
            events: [tokyoEvent, kyotoEvent], sessions: [tokyoSession, kyotoSession], home: Self.home, familiarPlaces: [], config: .default
        )

        #expect(trips.count == 1)
        #expect(trips.first?.eventIDs.count == 2)
    }

    @Test func noHomeStillProducesLowConfidenceSessionCandidate() {
        let (event1, session1) = makeEventWithSession(startOffsetDays: 10, durationHours: 6, latitude: 16.0544, longitude: 108.2022)

        let trips = DefaultTripDiscoveryEngine().detectTrips(events: [event1], sessions: [session1], home: nil, familiarPlaces: [], config: .default)

        #expect(trips.count == 1)
        #expect(trips[0].confidence < 0.6)
    }

    @Test func multiDaySessionsCreateTripWithoutAnyAcceptedEvent() {
        let (_, first) = makeEventWithSession(startOffsetDays: 10, durationHours: 2, latitude: 16.0544, longitude: 108.2022)
        let (_, second) = makeEventWithSession(startOffsetDays: 11, durationHours: 2, latitude: 16.0544, longitude: 108.2022)

        let trips = DefaultTripDiscoveryEngine().detectTrips(
            events: [], sessions: [first, second], home: Self.home, familiarPlaces: [], config: .default
        )

        #expect(trips.count == 1)
        #expect(trips[0].eventIDs.isEmpty)
        #expect(trips[0].travelContext.overnightCount == 1)
    }

    @Test func gpsLessSessionBridgesAwaySessions() {
        let (_, first) = makeEventWithSession(startOffsetDays: 10, durationHours: 2, latitude: 16.0544, longitude: 108.2022)
        let (_, last) = makeEventWithSession(startOffsetDays: 10.25, durationHours: 2, latitude: 16.0544, longitude: 108.2022)
        let missingGPS = PhotoSession(
            id: UUID(), startDate: Self.reference.addingTimeInterval(0.125 * 86400),
            endDate: Self.reference.addingTimeInterval(0.14 * 86400), centerLatitude: nil,
            centerLongitude: nil, geoCell: nil, assetIDs: ["missing-gps"], densityScore: 1
        )

        let trips = DefaultTripDiscoveryEngine().detectTrips(
            events: [], sessions: [first, missingGPS, last], home: Self.home,
            familiarPlaces: [], config: .default
        )

        #expect(trips.count == 1)
        #expect(trips[0].travelContext.eligibilityReasons.contains("bridgedUnknownGPS"))
    }

    @Test func consecutiveDaysAtFamiliarForeignDestinationRemainOneTrip() {
        let sessions = (0..<7).map { day in
            makeEventWithSession(startOffsetDays: 20 + Double(day), durationHours: 2, latitude: 35.6762, longitude: 139.6503).session
        }
        let familiar = FamiliarPlace(
            id: UUID(), clusterID: UUID(), centerLatitude: 35.6762, centerLongitude: 139.6503, confidence: 0.9
        )

        let trips = DefaultTripDiscoveryEngine().detectTrips(
            events: [], sessions: sessions, home: Self.home, familiarPlaces: [familiar], config: .default
        )

        #expect(trips.count == 1)
        #expect(trips[0].travelContext.overnightCount == 6)
    }

    // MARK: - Trip Eligibility V1 (SPRINT-NEXT § 5-9)

    /// AC: "Event gần Home trong thời gian ngắn không thành Trip" — 22km clears the .away
    /// boundary (localRadiusKm=20) but is still under every eligibility distance floor
    /// (overnight=25, dayTrip=30, international=150), even though the two events span a day
    /// boundary (overnightCount == 1).
    @Test func overnightTripTooCloseToHomeIsNotEligible() {
        let (event1, session1) = makeEventWithSession(startOffsetDays: 10, durationHours: 2, latitude: 21.2262, longitude: 105.8542)
        let (event2, session2) = makeEventWithSession(startOffsetDays: 11, durationHours: 2, latitude: 21.2262, longitude: 105.8542)

        let trips = DefaultTripDiscoveryEngine().detectTrips(
            events: [event1, event2], sessions: [session1, session2], home: Self.home, familiarPlaces: [], config: .default
        )

        #expect(trips.isEmpty)
    }

    /// Day Trip eligibility requires away + duration + distance + activity all together — two
    /// same-day events ~35km away, 5 hours apart, 2 sessions total clears every Day Trip floor.
    @Test func dayTripFarEnoughLongEnoughWithEnoughSessionsQualifies() {
        let (event1, session1) = makeEventWithSession(startOffsetDays: 20, durationHours: 2, latitude: 21.3429, longitude: 105.8542)
        let (event2, session2) = makeEventWithSession(startOffsetDays: 20.125, durationHours: 2, latitude: 21.3429, longitude: 105.8542)

        let trips = DefaultTripDiscoveryEngine().detectTrips(
            events: [event1, event2], sessions: [session1, session2], home: Self.home, familiarPlaces: [], config: .default
        )

        #expect(trips.count == 1)
        #expect(trips.first?.travelContext.eligibilityReasons.contains(TripEligibilityReason.dayTrip.rawValue) == true)
    }

    /// AC: a short (15 min), single-session, 21km stopover must not become a Trip — it fails
    /// every gate (no overnight, too short/too close for Day Trip, too close for international).
    @Test func shortNearbyStopoverIsNotEligibleForDayTrip() {
        let (event, session) = makeEventWithSession(startOffsetDays: 30, durationHours: 0.25, latitude: 21.2172, longitude: 105.8542)

        let trips = DefaultTripDiscoveryEngine().detectTrips(
            events: [event], sessions: [session], home: Self.home, familiarPlaces: [], config: .default
        )

        #expect(trips.isEmpty)
    }

    /// A single short (2h), far (160km) event can't clear the Day Trip gate (needs >= 4h) but
    /// is far enough to be a plausible international candidate — SPEC § 7's explicit exception
    /// that a single international Event can become a Trip on its own.
    @Test func internationalCandidateSingleEventBecomesProvisionallyEligible() {
        let (event, session) = makeEventWithSession(startOffsetDays: 40, durationHours: 2, latitude: 22.4658, longitude: 105.8542)

        let trips = DefaultTripDiscoveryEngine().detectTrips(
            events: [event], sessions: [session], home: Self.home, familiarPlaces: [], config: .default
        )

        #expect(trips.count == 1)
        #expect(trips.first?.travelContext.eligibilityReasons == [TripEligibilityReason.internationalCandidate.rawValue])
    }
}
