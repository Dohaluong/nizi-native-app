//
//  AlbumLayoutValidator.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Validates a decoded `AlbumLayoutLibrary` against the rules in
/// docs/ALBUM_LAYOUT_SYSTEM.md § Validation. A library that fails any rule must never be handed
/// to a renderer — `BundleAlbumLayoutRepository` calls this once, right after decoding, and
/// throws rather than caching an invalid library.
enum AlbumLayoutValidator {
    /// Aspect-ratio tolerance for the `square` category (§ 11.2) — ± this fraction of 1.0.
    private static let squareRatioTolerance = 0.05

    static func validate(_ library: AlbumLayoutLibrary, supportedSchemaVersion: Int = 1) throws {
        guard library.schemaVersion == supportedSchemaVersion else {
            throw AlbumLayoutError.unsupportedSchemaVersion(library.schemaVersion)
        }

        var seenLayoutIds = Set<String>()
        for layout in library.layouts {
            guard seenLayoutIds.insert(layout.id).inserted else {
                throw AlbumLayoutError.duplicateLayoutId(layout.id)
            }
        }

        for layout in library.layouts {
            try validate(layout)
        }
    }

    static func validate(_ layout: AlbumPageLayout) throws {
        guard (1...4).contains(layout.photoCount) else {
            throw AlbumLayoutError.invalidPhotoCount(layoutId: layout.id)
        }
        guard layout.slots.count == layout.photoCount else {
            throw AlbumLayoutError.slotCountMismatch(layoutId: layout.id)
        }
        guard layout.referenceCanvas.width > 0, layout.referenceCanvas.height > 0 else {
            throw AlbumLayoutError.invalidCanvas(layoutId: layout.id)
        }
        guard !layout.supportedFormats.isEmpty else {
            throw AlbumLayoutError.unsupportedFormat(layoutId: layout.id)
        }

        var seenSlotIds = Set<String>()
        var seenOrders = Set<Int>()
        for slot in layout.slots {
            guard seenSlotIds.insert(slot.id).inserted else {
                throw AlbumLayoutError.duplicateSlotId(layoutId: layout.id, slotId: slot.id)
            }
            guard seenOrders.insert(slot.order).inserted else {
                throw AlbumLayoutError.duplicateSlotOrder(layoutId: layout.id)
            }
            try validate(slot, in: layout)
        }

        for format in layout.supportedFormats {
            guard aspectRatio(of: layout.referenceCanvas, matches: format) else {
                throw AlbumLayoutError.aspectRatioMismatch(layoutId: layout.id, format: format)
            }
        }

        // § user request "Thêm chữ" — text blocks validate the same frame/canvas/uniqueness rules
        // slots do, but deliberately never touch `photoCount`/slot-count checks above (a layout's
        // text blocks are a separate, decorative collection — see `AlbumTextBlock`'s own doc
        // comment).
        var seenTextBlockIds = Set<String>()
        var seenTextBlockOrders = Set<Int>()
        for textBlock in layout.textBlocks {
            guard seenTextBlockIds.insert(textBlock.id).inserted else {
                throw AlbumLayoutError.duplicateTextBlockId(layoutId: layout.id, textBlockId: textBlock.id)
            }
            guard seenTextBlockOrders.insert(textBlock.order).inserted else {
                throw AlbumLayoutError.duplicateTextBlockOrder(layoutId: layout.id)
            }
            try validate(textBlock, in: layout)
        }
    }

    /// Validates a page's photo assignments against the layout it claims to use. A missing
    /// assignment for a slot is *not* an error here — the renderer shows a placeholder for that
    /// (§ 12.4) — but an assignment pointing at a slot the layout doesn't have, or two
    /// assignments claiming the same slot, are real data-integrity errors.
    static func validateAssignments(_ content: AlbumPageContent, layout: AlbumPageLayout) throws {
        let slotIds = Set(layout.slots.map(\.id))
        var seenSlotIds = Set<String>()
        for assignment in content.assignments {
            guard slotIds.contains(assignment.slotId) else {
                throw AlbumLayoutError.assignmentSlotNotFound(layoutId: layout.id, slotId: assignment.slotId)
            }
            guard seenSlotIds.insert(assignment.slotId).inserted else {
                throw AlbumLayoutError.duplicateAssignmentSlot(layoutId: layout.id, slotId: assignment.slotId)
            }
        }
    }

    private static func validate(_ slot: AlbumLayoutSlot, in layout: AlbumPageLayout) throws {
        let frame = slot.frame
        guard frame.width > 0, frame.height > 0, frame.x >= 0, frame.y >= 0, slot.cornerRadius >= 0 else {
            throw AlbumLayoutError.invalidFrame(layoutId: layout.id, slotId: slot.id)
        }
        let canvas = layout.referenceCanvas
        guard frame.x + frame.width <= canvas.width, frame.y + frame.height <= canvas.height else {
            throw AlbumLayoutError.slotOutsideCanvas(layoutId: layout.id, slotId: slot.id)
        }
    }

    private static func validate(_ textBlock: AlbumTextBlock, in layout: AlbumPageLayout) throws {
        let frame = textBlock.frame
        guard frame.width > 0, frame.height > 0, frame.x >= 0, frame.y >= 0 else {
            throw AlbumLayoutError.invalidTextBlockFrame(layoutId: layout.id, textBlockId: textBlock.id)
        }
        let canvas = layout.referenceCanvas
        guard frame.x + frame.width <= canvas.width, frame.y + frame.height <= canvas.height else {
            throw AlbumLayoutError.textBlockOutsideCanvas(layoutId: layout.id, textBlockId: textBlock.id)
        }
        guard textBlock.fontSize > 0 else {
            throw AlbumLayoutError.invalidTextBlockFontSize(layoutId: layout.id, textBlockId: textBlock.id)
        }
    }

    /// § 11.2 — square: ratio ≈ 1.0 within tolerance; portrait: ratio < 1.0; landscape: ratio > 1.0.
    private static func aspectRatio(of canvas: AlbumReferenceCanvas, matches format: AlbumPageFormat) -> Bool {
        let ratio = canvas.width / canvas.height
        switch format {
        case .square:
            return abs(ratio - 1.0) <= squareRatioTolerance
        case .portrait:
            return ratio < 1.0 - squareRatioTolerance
        case .landscape:
            return ratio > 1.0 + squareRatioTolerance
        }
    }
}
