//
//  AlbumLayoutDecodingTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

/// Exercises the real bundled `album-layouts.json` through `BundleAlbumLayoutRepository` — not
/// synthetic fixtures — so these tests fail if the shipped library itself ever regresses.
struct AlbumLayoutDecodingTests {
    private func makeRepository() -> BundleAlbumLayoutRepository {
        BundleAlbumLayoutRepository()
    }

    @Test func decodesLibrarySuccessfully() throws {
        let library = try makeRepository().loadLibrary()
        #expect(library.schemaVersion == 1)
        #expect(!library.layouts.isEmpty)
    }

    @Test func hasAtLeastTwelveLayouts() throws {
        let library = try makeRepository().loadLibrary()
        #expect(library.layouts.count >= 12)
    }

    @Test func hasLayoutsForEveryPhotoCountOneThroughFour() throws {
        let library = try makeRepository().loadLibrary()
        for count in 1...4 {
            let matches = library.layouts.filter { $0.photoCount == count }
            #expect(!matches.isEmpty, "expected at least one layout for photoCount=\(count)")
        }
    }

    @Test func everyPhotoCountHasAtLeastThreeVariants() throws {
        let library = try makeRepository().loadLibrary()
        for count in 1...4 {
            let matches = library.layouts.filter { $0.photoCount == count }
            #expect(matches.count >= 3, "expected >= 3 layouts for photoCount=\(count), got \(matches.count)")
        }
    }

    @Test func noDuplicateLayoutIds() throws {
        let library = try makeRepository().loadLibrary()
        let ids = library.layouts.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func noDuplicateSlotIdsWithinAnyLayout() throws {
        let library = try makeRepository().loadLibrary()
        for layout in library.layouts {
            let slotIds = layout.slots.map(\.id)
            #expect(Set(slotIds).count == slotIds.count, "duplicate slot id in \(layout.id)")
        }
    }

    @Test func slotCountMatchesPhotoCountForEveryLayout() throws {
        let library = try makeRepository().loadLibrary()
        for layout in library.layouts {
            #expect(layout.slots.count == layout.photoCount, "slot count mismatch in \(layout.id)")
        }
    }

    @Test func everySlotFrameIsPositiveAndWithinCanvas() throws {
        let library = try makeRepository().loadLibrary()
        for layout in library.layouts {
            let canvas = layout.referenceCanvas
            #expect(canvas.width > 0 && canvas.height > 0, "invalid canvas in \(layout.id)")
            for slot in layout.slots {
                let frame = slot.frame
                #expect(frame.width > 0 && frame.height > 0, "non-positive frame in \(layout.id)/\(slot.id)")
                #expect(frame.x >= 0 && frame.y >= 0, "negative origin in \(layout.id)/\(slot.id)")
                #expect(
                    frame.x + frame.width <= canvas.width && frame.y + frame.height <= canvas.height,
                    "slot exceeds canvas in \(layout.id)/\(slot.id)"
                )
            }
        }
    }

    @Test func filtersByPhotoCount() throws {
        let repository = makeRepository()
        let results = try repository.layouts(photoCount: 3, format: .square)
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.photoCount == 3 })
    }

    @Test func filtersByFormat() throws {
        let repository = makeRepository()
        let results = try repository.layouts(photoCount: 1, format: .square)
        #expect(results.allSatisfy { $0.supportedFormats.contains(.square) })
    }

    @Test func doesNotReturnLayoutsThatDontSupportTheRequestedFormat() throws {
        let repository = makeRepository()
        // The sample library ships square-only layouts this sprint, so requesting portrait
        // must come back empty rather than falling back to an incompatible square layout.
        let results = try repository.layouts(photoCount: 1, format: .portrait)
        #expect(results.isEmpty)
    }

    @Test func looksUpLayoutById() throws {
        let repository = makeRepository()
        let layout = try repository.layout(id: "square.3.hero-top")
        #expect(layout.photoCount == 3)
    }

    @Test func lookupOfMissingIdThrowsLayoutNotFound() throws {
        let repository = makeRepository()
        #expect(throws: AlbumLayoutError.layoutNotFound("does.not.exist")) {
            try repository.layout(id: "does.not.exist")
        }
    }

    @Test func defaultSelectorReturnsAStableLayoutPerPhotoCount() throws {
        let selector = DefaultAlbumLayoutSelector(repository: makeRepository())
        #expect(try selector.defaultLayout(photoCount: 1, format: .square).id == "square.1.inset")
        #expect(try selector.defaultLayout(photoCount: 2, format: .square).id == "square.2.vertical-split")
        #expect(try selector.defaultLayout(photoCount: 3, format: .square).id == "square.3.hero-top")
        #expect(try selector.defaultLayout(photoCount: 4, format: .square).id == "square.4.grid")
    }
}
