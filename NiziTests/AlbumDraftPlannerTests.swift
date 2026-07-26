//
//  AlbumDraftPlannerTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

/// A `PhotoPlaceResolving` that never touches `CLGeocoder` — every test in this file (and the
/// rest of NiziTests) must stay offline and deterministic.
private struct StubPlaceResolver: PhotoPlaceResolving {
    func resolvePlace(for coordinate: PhotoCoordinate) async throws -> PhotoPlace {
        throw PhotoLocationError.placeNotFound
    }
}

struct AlbumDraftPlannerTests {
    private func photo(id: String, eventId: String, orientation: PhotoOrientation, hourOffset: Int, isFavorite: Bool = false) -> AlbumPlanningPhoto {
        let (width, height): (Int, Int)
        switch orientation {
        case .landscape: (width, height) = (1600, 1200)
        case .portrait: (width, height) = (1200, 1600)
        case .square: (width, height) = (1400, 1400)
        }
        let base = DateComponents(calendar: .current, year: 2026, month: 1, day: 1).date!
        return AlbumPlanningPhoto(
            id: id, eventId: eventId, creationDate: Calendar.current.date(byAdding: .hour, value: hourOffset, to: base),
            pixelWidth: width, pixelHeight: height, coordinate: nil, place: nil,
            isFavorite: isFavorite, isEdited: false, burstIdentifier: nil, originalFilename: nil, exif: nil
        )
    }

    private func makePlanner() -> DefaultAlbumDraftPlanner {
        DefaultAlbumDraftPlanner(
            layoutRepository: BundleAlbumLayoutRepository(),
            locationEnricher: DefaultPhotoLocationEnricher(resolver: StubPlaceResolver())
        )
    }

    // MARK: - § 30.8 Final draft validation (via a real end-to-end run)

    @Test func sixPhotoDraftIsFullyValid() async throws {
        let event = AlbumPlanningEvent(
            id: "e1", title: "Trip", startDate: nil, endDate: nil, locationName: "Đà Lạt", latitude: nil, longitude: nil,
            selectedPhotos: [
                photo(id: "p0", eventId: "e1", orientation: .landscape, hourOffset: 0, isFavorite: true),
                photo(id: "p1", eventId: "e1", orientation: .portrait, hourOffset: 1),
                photo(id: "p2", eventId: "e1", orientation: .square, hourOffset: 2),
                photo(id: "p3", eventId: "e1", orientation: .landscape, hourOffset: 3),
                photo(id: "p4", eventId: "e1", orientation: .portrait, hourOffset: 4),
                photo(id: "p5", eventId: "e1", orientation: .landscape, hourOffset: 5)
            ]
        )
        let result = try await makePlanner().createDraft(from: AlbumPlanningInput(albumTitle: nil, events: [event]))
        let draft = result.draft
        let repository = BundleAlbumLayoutRepository()

        #expect(!draft.coverPhotoId.isEmpty)
        #expect(!draft.spreads.isEmpty)
        #expect(draft.planningVersion == DefaultAlbumDraftPlanner.planningVersion)
        for spread in draft.spreads {
            let leftCount = spread.leftPage.assignments.count
            let rightCount = spread.rightPage.assignments.count
            #expect((1...4).contains(leftCount))
            #expect((1...4).contains(rightCount))
            #expect((2...6).contains(leftCount + rightCount))
            #expect(spread.photoCount == leftCount + rightCount)

            for page in [spread.leftPage, spread.rightPage] {
                let layout = try repository.layout(id: page.layoutId)
                let content = AlbumPageContent(id: page.id, layoutId: page.layoutId, format: page.format, assignments: page.assignments)
                try AlbumLayoutValidator.validateAssignments(content, layout: layout)
            }
        }

        let totalAssigned = draft.spreads.reduce(0) { $0 + $1.photoCount }
        #expect(totalAssigned == 6)
        #expect(draft.totalPhotoCount == 6)
        #expect(draft.numberOfPages == draft.spreads.count * 2)
    }

    @Test func favoritePhotoIsChosenAsCover() async throws {
        let event = AlbumPlanningEvent(
            id: "e1", title: nil, startDate: nil, endDate: nil, locationName: nil, latitude: nil, longitude: nil,
            selectedPhotos: [
                photo(id: "plain", eventId: "e1", orientation: .landscape, hourOffset: 0),
                photo(id: "fav", eventId: "e1", orientation: .landscape, hourOffset: 1, isFavorite: true)
            ]
        )
        let result = try await makePlanner().createDraft(from: AlbumPlanningInput(albumTitle: nil, events: [event]))
        #expect(result.draft.coverPhotoId == "fav")
    }

    @Test func explicitAlbumTitleWins() async throws {
        let event = AlbumPlanningEvent(
            id: "e1", title: "Event Title", startDate: nil, endDate: nil, locationName: nil, latitude: nil, longitude: nil,
            selectedPhotos: [photo(id: "p0", eventId: "e1", orientation: .landscape, hourOffset: 0), photo(id: "p1", eventId: "e1", orientation: .landscape, hourOffset: 1)]
        )
        let result = try await makePlanner().createDraft(from: AlbumPlanningInput(albumTitle: "My Custom Title", events: [event]))
        #expect(result.draft.title == "My Custom Title")
    }

    @Test func singleEventTitleIsUsedWhenNoAlbumTitleGiven() async throws {
        let event = AlbumPlanningEvent(
            id: "e1", title: "Event Title", startDate: nil, endDate: nil, locationName: nil, latitude: nil, longitude: nil,
            selectedPhotos: [photo(id: "p0", eventId: "e1", orientation: .landscape, hourOffset: 0), photo(id: "p1", eventId: "e1", orientation: .landscape, hourOffset: 1)]
        )
        let result = try await makePlanner().createDraft(from: AlbumPlanningInput(albumTitle: nil, events: [event]))
        #expect(result.draft.title == "Event Title")
    }

    @Test func thirteenPhotosProduceThreeValidSpreadsNeverSixSixOne() async throws {
        let photos = (0..<13).map { photo(id: "p\($0)", eventId: "e1", orientation: [.landscape, .portrait, .square][$0 % 3], hourOffset: $0) }
        let event = AlbumPlanningEvent(id: "e1", title: nil, startDate: nil, endDate: nil, locationName: nil, latitude: nil, longitude: nil, selectedPhotos: photos)
        let result = try await makePlanner().createDraft(from: AlbumPlanningInput(albumTitle: nil, events: [event]))
        let draft = result.draft

        #expect(draft.spreads.count == 3)
        let sizes = draft.spreads.map(\.photoCount).sorted()
        #expect(sizes != [1, 6, 6].sorted())
        #expect(sizes.allSatisfy { (2...6).contains($0) })
        #expect(sizes.reduce(0, +) == 13)
    }

    // MARK: - § 22 Input validation

    @Test func noEventsThrows() async {
        await #expect(throws: AlbumPlanningError.noEvents) {
            try await makePlanner().createDraft(from: AlbumPlanningInput(albumTitle: nil, events: []))
        }
    }

    @Test func singlePhotoInputThrowsInsufficientPhotos() async {
        let event = AlbumPlanningEvent(
            id: "e1", title: nil, startDate: nil, endDate: nil, locationName: nil, latitude: nil, longitude: nil,
            selectedPhotos: [photo(id: "solo", eventId: "e1", orientation: .landscape, hourOffset: 0)]
        )
        await #expect(throws: AlbumPlanningError.insufficientPhotos(minimum: 2, actual: 1)) {
            try await makePlanner().createDraft(from: AlbumPlanningInput(albumTitle: nil, events: [event]))
        }
    }

    @Test func invalidPhotoDimensionsThrows() async {
        let event = AlbumPlanningEvent(
            id: "e1", title: nil, startDate: nil, endDate: nil, locationName: nil, latitude: nil, longitude: nil,
            selectedPhotos: [
                photo(id: "good", eventId: "e1", orientation: .landscape, hourOffset: 0),
                AlbumPlanningPhoto(
                    id: "bad", eventId: "e1", creationDate: nil, pixelWidth: 0, pixelHeight: 0,
                    coordinate: nil, place: nil, isFavorite: false, isEdited: false,
                    burstIdentifier: nil, originalFilename: nil, exif: nil
                )
            ]
        )
        await #expect(throws: AlbumPlanningError.invalidPhotoDimensions(photoId: "bad")) {
            try await makePlanner().createDraft(from: AlbumPlanningInput(albumTitle: nil, events: [event]))
        }
    }

    // MARK: - § 32 hard rules, checked end to end

    @Test func noPhotoIsLostOrDuplicatedInTheFinalDraft() async throws {
        let photos = (0..<17).map { photo(id: "p\($0)", eventId: "e1", orientation: [.landscape, .portrait, .square][$0 % 3], hourOffset: $0) }
        let event = AlbumPlanningEvent(id: "e1", title: nil, startDate: nil, endDate: nil, locationName: nil, latitude: nil, longitude: nil, selectedPhotos: photos)
        let result = try await makePlanner().createDraft(from: AlbumPlanningInput(albumTitle: nil, events: [event]))
        let draft = result.draft

        let assignedIDs = draft.spreads.flatMap { $0.leftPage.assignments + $0.rightPage.assignments }.map(\.photoId)
        #expect(Set(assignedIDs) == Set(photos.map(\.id)))
        #expect(assignedIDs.count == photos.count)
    }

    // MARK: - docs/specs/SPEC-ALBUM-PLANNER.md § 15.8 Planning Log

    @Test func logContainsEveryRequiredStage() async throws {
        let event = AlbumPlanningEvent(
            id: "e1", title: nil, startDate: nil, endDate: nil, locationName: nil, latitude: nil, longitude: nil,
            selectedPhotos: [
                photo(id: "p0", eventId: "e1", orientation: .landscape, hourOffset: 0, isFavorite: true),
                photo(id: "p1", eventId: "e1", orientation: .portrait, hourOffset: 1)
            ]
        )
        let result = try await makePlanner().createDraft(from: AlbumPlanningInput(albumTitle: nil, events: [event]))

        #expect(!result.log.entries(in: .cover).isEmpty)
        #expect(result.log.entries(in: .cover).contains { $0.code == "cover_selected" })
        #expect(!result.log.entries(in: .spread).isEmpty)
        #expect(result.log.entries(in: .spread).contains { $0.code == "spread_created" })
        #expect(result.log.entries(in: .layoutSelection).contains { $0.code == "layout_pair_selected" })
        #expect(result.log.entries(in: .assignment).contains { $0.code == "photo_assigned_to_slot" })
        #expect(result.log.entries(in: .validation).contains { $0.code == "draft_validation_succeeded" })
        #expect(!result.log.entries(in: .importance).isEmpty)

        // The persisted draft carries its own copy of the log too.
        #expect(result.draft.planningLog?.entries.isEmpty == false)
    }

    @Test func loggingDoesNotAffectScoringOutcome() async throws {
        // Same input planned twice must produce the identical Draft — the log's presence (and
        // its many `AlbumPlanningLogEntry(id:)` UUIDs) must never leak into any scoring decision.
        let event = AlbumPlanningEvent(
            id: "e1", title: nil, startDate: nil, endDate: nil, locationName: nil, latitude: nil, longitude: nil,
            selectedPhotos: (0..<6).map { photo(id: "p\($0)", eventId: "e1", orientation: [.landscape, .portrait, .square][$0 % 3], hourOffset: $0) }
        )
        let input = AlbumPlanningInput(albumTitle: nil, events: [event])
        let first = try await makePlanner().createDraft(from: input)
        let second = try await makePlanner().createDraft(from: input)

        #expect(first.draft.spreads.map { $0.leftPage.layoutId } == second.draft.spreads.map { $0.leftPage.layoutId })
        #expect(first.draft.spreads.map { $0.rightPage.layoutId } == second.draft.spreads.map { $0.rightPage.layoutId })
        #expect(first.draft.coverPhotoId == second.draft.coverPhotoId)
    }
}
