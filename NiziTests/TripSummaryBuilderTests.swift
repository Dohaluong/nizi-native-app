//
//  TripSummaryBuilderTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation
import Testing
@testable import Nizi

struct TripSummaryBuilderTests {
    @Test func photoCountSumsAcrossTripEvents() async throws {
        let eventA = PhotoEvent.tripSummaryFixture(assetIDs: ["a1", "a2"])
        let eventB = PhotoEvent.tripSummaryFixture(assetIDs: ["b1"])
        let trip = PhotoTrip.fixture(eventIDs: [eventA.id, eventB.id])
        let repository = StubPhotoEventRepository(events: [eventA, eventB])

        let summaries = try await TripSummaryBuilder.makeSummaries(trips: [trip], eventRepository: repository)

        #expect(summaries.first?.eventCount == 2)
        #expect(summaries.first?.photoCount == 3)
    }

    @Test func coverAssetPicksFirstEventInTripOrderWithNonNilCover() async throws {
        let noCover = PhotoEvent.tripSummaryFixture(coverAssetID: nil)
        let withCover = PhotoEvent.tripSummaryFixture(coverAssetID: "asset-cover")
        let trip = PhotoTrip.fixture(eventIDs: [noCover.id, withCover.id])
        // Deliberately out of trip order — proves the builder follows `trip.eventIDs`, not
        // whatever order the repository happened to return.
        let repository = StubPhotoEventRepository(events: [withCover, noCover])

        let summaries = try await TripSummaryBuilder.makeSummaries(trips: [trip], eventRepository: repository)

        #expect(summaries.first?.coverAssetID == "asset-cover")
    }

    @Test func orderingIsPreserved() async throws {
        let tripA = PhotoTrip.fixture()
        let tripB = PhotoTrip.fixture()
        let repository = StubPhotoEventRepository(events: [])

        let summaries = try await TripSummaryBuilder.makeSummaries(trips: [tripA, tripB], eventRepository: repository)

        #expect(summaries.map(\.id) == [tripA.id, tripB.id])
    }

    @Test func tripWithNoResolvableEventsDoesNotCrash() async throws {
        let trip = PhotoTrip.fixture(eventIDs: [UUID(), UUID()])
        let repository = StubPhotoEventRepository(events: [])

        let summaries = try await TripSummaryBuilder.makeSummaries(trips: [trip], eventRepository: repository)

        #expect(summaries.first?.eventCount == 0)
        #expect(summaries.first?.photoCount == 0)
        #expect(summaries.first?.coverAssetID == nil)
    }
}

private struct StubPhotoEventRepository: PhotoEventRepository {
    let events: [PhotoEvent]
    func replaceRebuildableEvents(_ events: [PhotoEvent]) async throws {}
    func fetchEvents(sortedBy order: PhotoEventSortOrder) async throws -> [PhotoEvent] { events }
    func fetchEvents(ids: [UUID]) async throws -> [PhotoEvent] {
        let idSet = Set(ids)
        return events.filter { idSet.contains($0.id) }
    }
    func fetchMemoryEvents() async throws -> [PhotoEvent] { events }
    func setEventLoved(eventID: UUID, isLoved: Bool) async throws {}
    func setEventPlace(eventID: UUID, place: EventPlace?, state: EventPlaceResolutionState) async throws {}
    func deleteEvent(id: UUID) async throws {}
    func mergeEvent(sourceID: UUID, into destinationID: UUID) async throws {}
}

private extension PhotoEvent {
    static func tripSummaryFixture(assetIDs: [String] = ["asset-1"], coverAssetID: String? = "asset-1") -> PhotoEvent {
        let now = Date()
        return PhotoEvent(
            id: UUID(), titleSuggestion: "Test", startDate: now, endDate: now,
            primaryLocationLabel: nil, eventType: .trip, score: 0.5, status: .new,
            sessionIDs: [UUID()], assetIDs: assetIDs, coverAssetID: coverAssetID,
            discoveryReasons: [], algorithmVersion: 1, createdAt: now, updatedAt: now
        )
    }
}

private extension PhotoTrip {
    static func fixture(startDate: Date = Date(), eventIDs: [UUID] = []) -> PhotoTrip {
        PhotoTrip(
            id: UUID(), startDate: startDate, endDate: startDate, eventIDs: eventIDs,
            primaryLatitude: nil, primaryLongitude: nil, primaryCountryCode: "JP",
            primaryPlaceName: "Tokyo, Nhật Bản", classification: .internationalTrip, confidence: 0.9,
            travelContext: TravelContext(
                homeCountryCode: "VN", maxDistanceFromHomeKm: 3000, overnightCount: 6,
                countryCodes: ["JP"], hasDepartureFromHome: true, hasReturnToHome: true
            )
        )
    }
}
