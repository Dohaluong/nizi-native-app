//
//  AlbumViewerItemBuilderTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

/// docs/specs/ADDENDUM-001.md § 23 "Viewer item builder"
struct AlbumViewerItemBuilderTests {
    private func reference(_ id: String) -> AlbumPhotoReference {
        AlbumPhotoReference(id: id, source: .applePhotos, sourceIdentifier: id, originalFilename: nil)
    }

    private func page(id: String, photoCount: Int) -> AlbumDraftPage {
        AlbumDraftPage(
            id: id, order: 0, layoutId: "square.\(photoCount).test", format: .square,
            assignments: (0..<photoCount).map { AlbumPhotoAssignment(id: "\(id)-a\($0)", slotId: "photo-\($0)", photo: reference("\(id)-p\($0)")) },
            sourceEventIds: ["e1"]
        )
    }

    private func spread(id: String, order: Int, leftCount: Int, rightCount: Int) -> AlbumDraftSpread {
        AlbumDraftSpread(
            id: id, order: order, sourceEventIds: ["e1"],
            leftPage: page(id: "\(id)-left", photoCount: leftCount),
            rightPage: page(id: "\(id)-right", photoCount: rightCount)
        )
    }

    private func draft(spreads: [AlbumDraftSpread]) -> AlbumDraft {
        AlbumDraft(
            id: "draft-1", title: "Test Album", subtitle: nil, coverPhotoId: "cover-asset",
            startDate: nil, endDate: nil, primaryLocationName: nil, primaryPlace: nil,
            sourceEvents: [], spreads: spreads, createdAt: Date(), planningVersion: 1, planningLog: nil
        )
    }

    @Test func coverIsAlwaysTheFirstItem() {
        let items = DefaultAlbumViewerItemBuilder().makeItems(from: draft(spreads: [spread(id: "s1", order: 0, leftCount: 2, rightCount: 2)]))
        guard case .cover = items.first else {
            Issue.record("expected the first item to be .cover")
            return
        }
    }

    @Test func leftPageComesBeforeRightPage() {
        let items = DefaultAlbumViewerItemBuilder().makeItems(from: draft(spreads: [spread(id: "s1", order: 0, leftCount: 2, rightCount: 3)]))
        let pageIds = items.compactMap { item -> String? in
            guard case let .page(page) = item else { return nil }
            return page.id
        }
        #expect(pageIds == ["s1-left", "s1-right"])
    }

    @Test func spreadOrderIsPreserved() {
        let d = draft(spreads: [
            spread(id: "s1", order: 0, leftCount: 2, rightCount: 2),
            spread(id: "s2", order: 1, leftCount: 3, rightCount: 3)
        ])
        let pageIds = DefaultAlbumViewerItemBuilder().makeItems(from: d).compactMap { item -> String? in
            guard case let .page(page) = item else { return nil }
            return page.id
        }
        #expect(pageIds == ["s1-left", "s1-right", "s2-left", "s2-right"])
    }

    @Test func pageNumberingStartsAtOne() {
        let d = draft(spreads: [spread(id: "s1", order: 0, leftCount: 2, rightCount: 2)])
        let pageNumbers = DefaultAlbumViewerItemBuilder().makeItems(from: d).compactMap { item -> Int? in
            guard case let .page(page) = item else { return nil }
            return page.pageNumber
        }
        #expect(pageNumbers == [1, 2])
    }

    @Test func coverIsNotCountedAsAPage() {
        let d = draft(spreads: [spread(id: "s1", order: 0, leftCount: 2, rightCount: 2)])
        let items = DefaultAlbumViewerItemBuilder().makeItems(from: d)
        let pageCount = items.filter { if case .page = $0 { return true } else { return false } }.count
        #expect(items.count == pageCount + 1) // +1 for the Cover
    }

    @Test func twoSpreadsProduceFourPageViewerItems() {
        let d = draft(spreads: [
            spread(id: "s1", order: 0, leftCount: 2, rightCount: 2),
            spread(id: "s2", order: 1, leftCount: 4, rightCount: 3)
        ])
        let items = DefaultAlbumViewerItemBuilder().makeItems(from: d)
        let pages = items.compactMap { item -> AlbumViewerPage? in
            guard case let .page(page) = item else { return nil }
            return page
        }
        #expect(pages.count == 4)
        #expect(pages.allSatisfy { $0.totalPageCount == 4 })
    }

    @Test func positionInSpreadIsCorrect() {
        let d = draft(spreads: [spread(id: "s1", order: 0, leftCount: 2, rightCount: 2)])
        let pages = DefaultAlbumViewerItemBuilder().makeItems(from: d).compactMap { item -> AlbumViewerPage? in
            guard case let .page(page) = item else { return nil }
            return page
        }
        #expect(pages[0].positionInSpread == .left)
        #expect(pages[1].positionInSpread == .right)
        #expect(pages[0].spreadId == "s1")
        #expect(pages[1].spreadId == "s1")
    }
}
