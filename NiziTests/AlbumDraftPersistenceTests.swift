//
//  AlbumDraftPersistenceTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

/// docs/specs/SPEC-ALBUM-PLANNER.md § 15.9 — plain `Codable` round trips, no SwiftData
/// involved (that's exercised separately, e.g. by `SwiftDataMemoryDiscoveryStoreTests`'s pattern
/// for other stores) — this just confirms every new type actually encodes/decodes correctly.
struct AlbumDraftPersistenceTests {
    private func place() -> PhotoPlace {
        PhotoPlace(
            coordinate: PhotoCoordinate(latitude: -33.8568, longitude: 151.2153)!, name: "Sydney Opera House",
            subLocality: nil, locality: "Sydney", subAdministrativeArea: nil, administrativeArea: "NSW",
            country: "Australia", isoCountryCode: "AU", displayName: "Sydney Opera House, Sydney"
        )
    }

    private func sampleDraft() -> AlbumDraft {
        let assignment = AlbumPhotoAssignment(id: "a1", slotId: "photo-1", photoId: "asset-1")
        let leftPage = AlbumDraftPage(
            id: "spread-0-left", order: 0, layoutId: "square.1.inset", format: .square,
            assignments: [assignment], sourceEventIds: ["e1"],
            heroPhotoId: "asset-1", primaryPlace: place(), layoutScore: 97.5, assignmentScore: 100
        )
        let rightPage = AlbumDraftPage(
            id: "spread-0-right", order: 1, layoutId: "square.1.inset", format: .square,
            assignments: [assignment], sourceEventIds: ["e1"],
            heroPhotoId: nil, primaryPlace: nil, layoutScore: nil, assignmentScore: nil
        )
        let spread = AlbumDraftSpread(
            id: "spread-0", order: 0, sourceEventIds: ["e1"], leftPage: leftPage, rightPage: rightPage,
            orientationSummary: AlbumPhotoOrientationSummary(photos: []), primaryPlace: place(),
            heroPhotoId: "asset-1", planningScore: 197.5
        )
        var log = AlbumPlanningLog()
        log.add(AlbumPlanningLogEntry(stage: .cover, code: "cover_selected", message: "test", metadata: ["photoId": "asset-1"]))

        return AlbumDraft(
            id: "draft-1", title: "Sydney", subtitle: nil, coverPhotoId: "asset-1",
            startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 1000),
            primaryLocationName: "Sydney", primaryPlace: place(),
            sourceEvents: [AlbumSourceEvent(id: "e1", title: "Trip", selectedPhotoCount: 1, startDate: nil, endDate: nil, place: place())],
            spreads: [spread], createdAt: Date(timeIntervalSince1970: 500),
            planningVersion: 1, planningLog: log
        )
    }

    @Test func draftRoundTripsThroughJSON() throws {
        let original = sampleDraft()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AlbumDraft.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.spreads.count == original.spreads.count)
        #expect(decoded.totalPhotoCount == original.totalPhotoCount)
        #expect(decoded.planningVersion == 1)
    }

    @Test func planningLogRoundTrips() throws {
        let original = sampleDraft()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AlbumDraft.self, from: data)

        #expect(decoded.planningLog?.entries.count == original.planningLog?.entries.count)
        #expect(decoded.planningLog?.entries.first?.code == "cover_selected")
    }

    @Test func placeRoundTrips() throws {
        let original = sampleDraft()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AlbumDraft.self, from: data)

        #expect(decoded.primaryPlace?.displayName == original.primaryPlace?.displayName)
        #expect(decoded.spreads.first?.leftPage.primaryPlace?.locality == "Sydney")
    }

    @Test func importanceRoundTrips() throws {
        let importance = PhotoImportance(totalScore: 42.5, reasons: [.favorite(30), .resolution(12.5)])
        let data = try JSONEncoder().encode(importance)
        let decoded = try JSONDecoder().decode(PhotoImportance.self, from: data)
        #expect(decoded == importance)
    }

    @Test func draftWithoutNewFieldsStillDecodes() throws {
        // Simulates a draft persisted *before* this schema change — every new field is either
        // Optional or computed, so a JSON blob missing them entirely must still decode.
        let legacyJSON = """
        {
            "id": "legacy-1",
            "title": "Old Album",
            "coverPhotoId": "asset-1",
            "sourceEvents": [],
            "spreads": [],
            "createdAt": 0
        }
        """
        let decoded = try JSONDecoder().decode(AlbumDraft.self, from: Data(legacyJSON.utf8))
        #expect(decoded.id == "legacy-1")
        #expect(decoded.planningVersion == nil)
        #expect(decoded.primaryPlace == nil)
        #expect(decoded.totalPhotoCount == 0)
    }
}
