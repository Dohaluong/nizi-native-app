//
//  AlbumPhotoSlotAssignerTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

struct AlbumPhotoSlotAssignerTests {
    private func photo(id: String, width: Int, height: Int) -> AlbumPlanningPhoto {
        AlbumPlanningPhoto(
            id: id, eventId: "e", creationDate: nil, pixelWidth: width, pixelHeight: height,
            coordinate: nil, place: nil, isFavorite: false, isEdited: false,
            burstIdentifier: nil, originalFilename: nil, exif: nil
        )
    }

    private func slot(id: String, order: Int, orientation: AlbumSlotOrientation, role: AlbumLayoutSlotRole = .supporting) -> AlbumLayoutSlot {
        AlbumLayoutSlot(
            id: id, order: order, role: role, preferredOrientation: orientation,
            frame: AlbumLayoutFrame(x: 0, y: 0, width: 100, height: 100), contentMode: .fill, cornerRadius: 0
        )
    }

    private func layout(slots: [AlbumLayoutSlot]) -> AlbumPageLayout {
        AlbumPageLayout(
            id: "test-layout", name: "Test", nameKey: "test", photoCount: slots.count,
            supportedFormats: [.square], referenceCanvas: AlbumReferenceCanvas(width: 1000, height: 1000),
            background: AlbumLayoutBackground(type: .solid, value: "#FFFFFF"), slots: slots
        )
    }

    @Test func landscapePhotoPrefersLandscapeSlot() {
        let landscape = photo(id: "landscape", width: 1600, height: 1200)
        let portrait = photo(id: "portrait", width: 1200, height: 1600)
        let layout = layout(slots: [slot(id: "s1", order: 0, orientation: .landscape), slot(id: "s2", order: 1, orientation: .portrait)])

        let result = DefaultAlbumPhotoSlotAssigner().assign(photos: [landscape, portrait], to: layout)
        let bySlot = Dictionary(uniqueKeysWithValues: result.assignments.map { ($0.slotId, $0.photoId) })
        #expect(bySlot["s1"] == "landscape")
        #expect(bySlot["s2"] == "portrait")
    }

    @Test func portraitPhotoPrefersPortraitSlot() {
        let landscape = photo(id: "landscape", width: 1600, height: 1200)
        let portrait = photo(id: "portrait", width: 1200, height: 1600)
        let layout = layout(slots: [slot(id: "s1", order: 0, orientation: .portrait), slot(id: "s2", order: 1, orientation: .landscape)])

        let result = DefaultAlbumPhotoSlotAssigner().assign(photos: [landscape, portrait], to: layout)
        let bySlot = Dictionary(uniqueKeysWithValues: result.assignments.map { ($0.slotId, $0.photoId) })
        #expect(bySlot["s1"] == "portrait")
        #expect(bySlot["s2"] == "landscape")
    }

    @Test func squarePhotoPrefersSquareSlot() {
        let square = photo(id: "square", width: 1400, height: 1400)
        let landscape = photo(id: "landscape", width: 1600, height: 1200)
        let layout = layout(slots: [slot(id: "s1", order: 0, orientation: .square), slot(id: "s2", order: 1, orientation: .landscape)])

        let result = DefaultAlbumPhotoSlotAssigner().assign(photos: [square, landscape], to: layout)
        let bySlot = Dictionary(uniqueKeysWithValues: result.assignments.map { ($0.slotId, $0.photoId) })
        #expect(bySlot["s1"] == "square")
    }

    @Test func landscapeCanFillASquareSlot() {
        // A single landscape photo into a single square slot must not fail/placeholder — it's an
        // acceptable (if not perfect) match per § 8.1.
        let landscape = photo(id: "landscape", width: 1600, height: 1200)
        let layout = layout(slots: [slot(id: "s1", order: 0, orientation: .square)])
        let result = DefaultAlbumPhotoSlotAssigner().assign(photos: [landscape], to: layout)
        #expect(result.assignments.count == 1)
        #expect(result.assignments[0].photoId == "landscape")
        #expect(result.score > 0)
    }

    @Test func portraitCanFillASquareSlot() {
        let portrait = photo(id: "portrait", width: 1200, height: 1600)
        let layout = layout(slots: [slot(id: "s1", order: 0, orientation: .square)])
        let result = DefaultAlbumPhotoSlotAssigner().assign(photos: [portrait], to: layout)
        #expect(result.assignments.count == 1)
        #expect(result.score > 0)
    }

    @Test func everySlotGetsExactlyOnePhotoNoDuplicates() {
        let photos = (0..<4).map { photo(id: "p\($0)", width: 1600, height: 1200) }
        let layout = layout(slots: (0..<4).map { slot(id: "s\($0)", order: $0, orientation: .landscape) })
        let result = DefaultAlbumPhotoSlotAssigner().assign(photos: photos, to: layout)

        #expect(result.assignments.count == 4)
        #expect(Set(result.assignments.map(\.slotId)).count == 4)
        #expect(Set(result.assignments.map(\.photoId)).count == 4)
    }

    @Test func mismatchedCountReturnsEmptyRatherThanCrashing() {
        let photos = [photo(id: "only-one", width: 1600, height: 1200)]
        let layout = layout(slots: [slot(id: "s1", order: 0, orientation: .landscape), slot(id: "s2", order: 1, orientation: .landscape)])
        let result = DefaultAlbumPhotoSlotAssigner().assign(photos: photos, to: layout)
        #expect(result.assignments.isEmpty)
    }
}
