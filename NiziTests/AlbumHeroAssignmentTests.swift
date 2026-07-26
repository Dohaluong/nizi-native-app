//
//  AlbumHeroAssignmentTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

/// docs/specs/SPEC-ALBUM-PLANNER.md § 15.6 — importance-driven hero slot preference, and its
/// limits relative to orientation.
struct AlbumHeroAssignmentTests {
    private func photo(id: String, orientation: PhotoOrientation, importance: Double) -> AlbumPlanningPhoto {
        let (width, height): (Int, Int)
        switch orientation {
        case .landscape: (width, height) = (1600, 1200)
        case .portrait: (width, height) = (1200, 1600)
        case .square: (width, height) = (1400, 1400)
        }
        return AlbumPlanningPhoto(
            id: id, eventId: "e", creationDate: nil, pixelWidth: width, pixelHeight: height,
            coordinate: nil, place: nil, isFavorite: false, isEdited: false,
            burstIdentifier: nil, originalFilename: nil, exif: nil,
            importance: PhotoImportance(totalScore: importance, reasons: [])
        )
    }

    private func heroLayout(orientation: AlbumSlotOrientation, secondOrientation: AlbumSlotOrientation) -> AlbumPageLayout {
        AlbumPageLayout(
            id: "test", name: "Test", nameKey: "test", photoCount: 2, supportedFormats: [.square],
            referenceCanvas: AlbumReferenceCanvas(width: 1000, height: 1000),
            background: AlbumLayoutBackground(type: .solid, value: "#FFFFFF"),
            slots: [
                AlbumLayoutSlot(id: "hero-slot", order: 0, role: .hero, preferredOrientation: orientation, frame: AlbumLayoutFrame(x: 0, y: 0, width: 500, height: 500), contentMode: .fill, cornerRadius: 0),
                AlbumLayoutSlot(id: "other-slot", order: 1, role: .supporting, preferredOrientation: secondOrientation, frame: AlbumLayoutFrame(x: 500, y: 0, width: 500, height: 500), contentMode: .fill, cornerRadius: 0)
            ]
        )
    }

    @Test func higherImportancePhotoPrefersHeroSlotWhenOrientationIsTied() {
        // Both photos are landscape and both slots are landscape — orientation is a wash, so
        // importance should decide which one lands in the hero slot.
        let layout = heroLayout(orientation: .landscape, secondOrientation: .landscape)
        let important = photo(id: "important", orientation: .landscape, importance: 90)
        let unimportant = photo(id: "unimportant", orientation: .landscape, importance: 5)

        let result = DefaultAlbumPhotoSlotAssigner().assign(photos: [important, unimportant], to: layout)
        let heroPhotoId = result.assignments.first { $0.slotId == "hero-slot" }?.photoId
        #expect(heroPhotoId == "important")
    }

    @Test func goodOrientationMatchStillBeatsHighImportanceWithSevereMismatch() {
        // The hero slot is landscape-preferred. `important` is portrait (severe mismatch, +20),
        // `plain` is landscape (perfect match, +100) with zero importance — the 80-point
        // orientation gap must not be overcome by the ≤20-point importance bonus.
        let layout = heroLayout(orientation: .landscape, secondOrientation: .portrait)
        let important = photo(id: "important", orientation: .portrait, importance: 100)
        let plain = photo(id: "plain", orientation: .landscape, importance: 0)

        let result = DefaultAlbumPhotoSlotAssigner().assign(photos: [important, plain], to: layout)
        let heroPhotoId = result.assignments.first { $0.slotId == "hero-slot" }?.photoId
        #expect(heroPhotoId == "plain")
    }

    @Test func heroAssignmentNeverDuplicatesAPhotoAcrossSlots() {
        let layout = heroLayout(orientation: .landscape, secondOrientation: .portrait)
        let a = photo(id: "a", orientation: .landscape, importance: 50)
        let b = photo(id: "b", orientation: .portrait, importance: 50)
        let result = DefaultAlbumPhotoSlotAssigner().assign(photos: [a, b], to: layout)
        #expect(Set(result.assignments.map(\.photoId)).count == 2)
        #expect(Set(result.assignments.map(\.slotId)).count == 2)
    }
}
