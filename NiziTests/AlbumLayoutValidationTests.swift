//
//  AlbumLayoutValidationTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

/// Exercises `AlbumLayoutValidator` directly against hand-built fixtures — one rule per test,
/// each mutating a single known-valid layout so the failure clearly maps to the rule under test.
struct AlbumLayoutValidationTests {
    private func makeSlot(
        id: String = "photo-1",
        order: Int = 0,
        role: AlbumLayoutSlotRole = .hero,
        preferredOrientation: AlbumSlotOrientation = .square,
        frame: AlbumLayoutFrame = AlbumLayoutFrame(x: 60, y: 60, width: 880, height: 880),
        contentMode: AlbumSlotContentMode = .fill,
        cornerRadius: Double = 0
    ) -> AlbumLayoutSlot {
        AlbumLayoutSlot(
            id: id, order: order, role: role, preferredOrientation: preferredOrientation,
            frame: frame, contentMode: contentMode, cornerRadius: cornerRadius
        )
    }

    private func makeLayout(
        id: String = "square.1.test",
        photoCount: Int = 1,
        supportedFormats: [AlbumPageFormat] = [.square],
        referenceCanvas: AlbumReferenceCanvas = AlbumReferenceCanvas(width: 1000, height: 1000),
        slots: [AlbumLayoutSlot]? = nil
    ) -> AlbumPageLayout {
        AlbumPageLayout(
            id: id,
            name: "Test",
            nameKey: "album.layout.test",
            photoCount: photoCount,
            supportedFormats: supportedFormats,
            referenceCanvas: referenceCanvas,
            background: AlbumLayoutBackground(type: .solid, value: "#FFFFFF"),
            slots: slots ?? [makeSlot()]
        )
    }

    // MARK: - Valid case

    @Test func validLayoutPassesValidation() throws {
        try AlbumLayoutValidator.validate(makeLayout())
    }

    @Test func validLibraryPassesValidation() throws {
        let library = AlbumLayoutLibrary(schemaVersion: 1, layouts: [makeLayout()])
        try AlbumLayoutValidator.validate(library)
    }

    // MARK: - Schema version

    @Test func unsupportedSchemaVersionThrows() {
        let library = AlbumLayoutLibrary(schemaVersion: 99, layouts: [])
        #expect(throws: AlbumLayoutError.unsupportedSchemaVersion(99)) {
            try AlbumLayoutValidator.validate(library)
        }
    }

    // MARK: - Layout identity

    @Test func duplicateLayoutIdThrows() {
        let library = AlbumLayoutLibrary(schemaVersion: 1, layouts: [makeLayout(id: "dup"), makeLayout(id: "dup")])
        #expect(throws: AlbumLayoutError.duplicateLayoutId("dup")) {
            try AlbumLayoutValidator.validate(library)
        }
    }

    // MARK: - Photo count / slot count

    @Test func photoCountOutsideOneToFourThrows() {
        let layout = makeLayout(photoCount: 5, slots: [makeSlot(), makeSlot(id: "photo-2", order: 1), makeSlot(id: "photo-3", order: 2), makeSlot(id: "photo-4", order: 3), makeSlot(id: "photo-5", order: 4)])
        #expect(throws: AlbumLayoutError.invalidPhotoCount(layoutId: layout.id)) {
            try AlbumLayoutValidator.validate(layout)
        }
    }

    @Test func slotCountMismatchThrows() {
        let layout = makeLayout(photoCount: 2, slots: [makeSlot()])
        #expect(throws: AlbumLayoutError.slotCountMismatch(layoutId: layout.id)) {
            try AlbumLayoutValidator.validate(layout)
        }
    }

    // MARK: - Slot identity

    @Test func duplicateSlotIdThrows() {
        let slots = [makeSlot(id: "same", order: 0), makeSlot(id: "same", order: 1)]
        let layout = makeLayout(photoCount: 2, slots: slots)
        #expect(throws: AlbumLayoutError.duplicateSlotId(layoutId: layout.id, slotId: "same")) {
            try AlbumLayoutValidator.validate(layout)
        }
    }

    @Test func duplicateSlotOrderThrows() {
        let slots = [makeSlot(id: "photo-1", order: 0), makeSlot(id: "photo-2", order: 0)]
        let layout = makeLayout(photoCount: 2, slots: slots)
        #expect(throws: AlbumLayoutError.duplicateSlotOrder(layoutId: layout.id)) {
            try AlbumLayoutValidator.validate(layout)
        }
    }

    // MARK: - Canvas / frame geometry

    @Test func nonPositiveCanvasThrows() {
        let layout = makeLayout(referenceCanvas: AlbumReferenceCanvas(width: 0, height: 1000))
        #expect(throws: AlbumLayoutError.invalidCanvas(layoutId: layout.id)) {
            try AlbumLayoutValidator.validate(layout)
        }
    }

    @Test func nonPositiveSlotFrameThrows() {
        let layout = makeLayout(slots: [makeSlot(frame: AlbumLayoutFrame(x: 0, y: 0, width: 0, height: 100))])
        #expect(throws: AlbumLayoutError.invalidFrame(layoutId: layout.id, slotId: "photo-1")) {
            try AlbumLayoutValidator.validate(layout)
        }
    }

    @Test func negativeSlotOriginThrows() {
        let layout = makeLayout(slots: [makeSlot(frame: AlbumLayoutFrame(x: -10, y: 0, width: 100, height: 100))])
        #expect(throws: AlbumLayoutError.invalidFrame(layoutId: layout.id, slotId: "photo-1")) {
            try AlbumLayoutValidator.validate(layout)
        }
    }

    @Test func negativeCornerRadiusThrows() {
        let layout = makeLayout(slots: [makeSlot(frame: AlbumLayoutFrame(x: 0, y: 0, width: 100, height: 100), cornerRadius: -1)])
        #expect(throws: AlbumLayoutError.invalidFrame(layoutId: layout.id, slotId: "photo-1")) {
            try AlbumLayoutValidator.validate(layout)
        }
    }

    @Test func slotExceedingCanvasThrows() {
        let layout = makeLayout(slots: [makeSlot(frame: AlbumLayoutFrame(x: 900, y: 0, width: 200, height: 100))])
        #expect(throws: AlbumLayoutError.slotOutsideCanvas(layoutId: layout.id, slotId: "photo-1")) {
            try AlbumLayoutValidator.validate(layout)
        }
    }

    // MARK: - Formats

    @Test func emptySupportedFormatsThrows() {
        let layout = makeLayout(supportedFormats: [])
        #expect(throws: AlbumLayoutError.unsupportedFormat(layoutId: layout.id)) {
            try AlbumLayoutValidator.validate(layout)
        }
    }

    @Test func squareFormatWithNonSquareCanvasThrows() {
        // 1000x1400 is portrait-shaped, well outside the 5% square tolerance.
        let layout = makeLayout(
            supportedFormats: [.square],
            referenceCanvas: AlbumReferenceCanvas(width: 1000, height: 1400),
            slots: [makeSlot(frame: AlbumLayoutFrame(x: 0, y: 0, width: 1000, height: 1400))]
        )
        #expect(throws: AlbumLayoutError.aspectRatioMismatch(layoutId: layout.id, format: .square)) {
            try AlbumLayoutValidator.validate(layout)
        }
    }

    @Test func portraitFormatAcceptsPortraitCanvas() throws {
        let layout = makeLayout(
            supportedFormats: [.portrait],
            referenceCanvas: AlbumReferenceCanvas(width: 1000, height: 1400),
            slots: [makeSlot(frame: AlbumLayoutFrame(x: 0, y: 0, width: 1000, height: 1400))]
        )
        try AlbumLayoutValidator.validate(layout)
    }

    // MARK: - Assignment validation

    @Test func assignmentPointingAtValidSlotPasses() throws {
        let layout = makeLayout()
        let content = AlbumPageContent(
            id: "page-1",
            layoutId: layout.id,
            format: .square,
            assignments: [AlbumPhotoAssignment(id: "a1", slotId: "photo-1", photoId: "asset-1")]
        )
        try AlbumLayoutValidator.validateAssignments(content, layout: layout)
    }

    @Test func missingAssignmentForASlotIsNotAnError() throws {
        // No assignments at all — the renderer shows a placeholder for the unassigned slot;
        // this is not a validation failure.
        let layout = makeLayout()
        let content = AlbumPageContent(id: "page-1", layoutId: layout.id, format: .square, assignments: [])
        try AlbumLayoutValidator.validateAssignments(content, layout: layout)
    }

    @Test func assignmentPointingAtUnknownSlotThrows() {
        let layout = makeLayout()
        let content = AlbumPageContent(
            id: "page-1",
            layoutId: layout.id,
            format: .square,
            assignments: [AlbumPhotoAssignment(id: "a1", slotId: "no-such-slot", photoId: "asset-1")]
        )
        #expect(throws: AlbumLayoutError.assignmentSlotNotFound(layoutId: layout.id, slotId: "no-such-slot")) {
            try AlbumLayoutValidator.validateAssignments(content, layout: layout)
        }
    }

    @Test func twoAssignmentsClaimingTheSameSlotThrows() {
        let layout = makeLayout(photoCount: 2, slots: [makeSlot(id: "photo-1", order: 0), makeSlot(id: "photo-2", order: 1)])
        let content = AlbumPageContent(
            id: "page-1",
            layoutId: layout.id,
            format: .square,
            assignments: [
                AlbumPhotoAssignment(id: "a1", slotId: "photo-1", photoId: "asset-1"),
                AlbumPhotoAssignment(id: "a2", slotId: "photo-1", photoId: "asset-2")
            ]
        )
        #expect(throws: AlbumLayoutError.duplicateAssignmentSlot(layoutId: layout.id, slotId: "photo-1")) {
            try AlbumLayoutValidator.validateAssignments(content, layout: layout)
        }
    }
}
