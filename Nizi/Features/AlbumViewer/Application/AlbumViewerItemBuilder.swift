//
//  AlbumViewerItemBuilder.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Flattens a persisted `AlbumDraft` (Spreads of two Pages each) into the single-page Viewer's
/// linear item list — Cover, then every non-empty Page in Spread/left-then-right order. See
/// docs/specs/ADDENDUM-001.md § 6.
protocol AlbumViewerItemBuilding {
    func makeItems(from draft: AlbumDraft) -> [AlbumViewerItem]
}

struct DefaultAlbumViewerItemBuilder: AlbumViewerItemBuilding {
    func makeItems(from draft: AlbumDraft) -> [AlbumViewerItem] {
        var items: [AlbumViewerItem] = [.cover(makeCoverConfiguration(from: draft))]

        // § 6 rule 7 — a Page with no assignments is never shown; § 22.2 guarantees this
        // shouldn't happen for a valid Draft, but the builder itself doesn't silently drop
        // anything a validator should have caught (rule 9) — it just never *renders* an empty
        // Page, which is a presentation concern, not a data-integrity one.
        struct Entry {
            let spreadIndex: Int
            let spreadId: String
            let position: AlbumSpreadPagePosition
            let page: AlbumDraftPage
        }

        var entries: [Entry] = []
        for (spreadIndex, spread) in draft.spreads.enumerated() {
            if !spread.leftPage.assignments.isEmpty {
                entries.append(Entry(spreadIndex: spreadIndex, spreadId: spread.id, position: .left, page: spread.leftPage))
            }
            if !spread.rightPage.assignments.isEmpty {
                entries.append(Entry(spreadIndex: spreadIndex, spreadId: spread.id, position: .right, page: spread.rightPage))
            }
        }

        let totalPageCount = entries.count
        for (index, entry) in entries.enumerated() {
            items.append(
                .page(
                    AlbumViewerPage(
                        id: entry.page.id, page: entry.page, pageNumber: index + 1, totalPageCount: totalPageCount,
                        spreadId: entry.spreadId, spreadIndex: entry.spreadIndex, positionInSpread: entry.position
                    )
                )
            )
        }

        return items
    }

    private func makeCoverConfiguration(from draft: AlbumDraft) -> AlbumCoverConfiguration {
        AlbumCoverConfiguration(
            photo: draft.coverPhotoReference,
            title: draft.title,
            subtitle: nil,
            dateText: Self.dateText(draft: draft),
            // A user-edited `primaryLocationName` (free text, no coordinate required) wins over
            // the geocoded `primaryPlace.displayName` — see `AlbumInfoEditSheet`.
            placeText: draft.primaryLocationName ?? draft.primaryPlace?.displayName,
            styleId: AlbumCoverConfiguration.classicStyleId
        )
    }

    private static func dateText(draft: AlbumDraft) -> String? {
        guard let start = draft.startDate else { return nil }
        guard let end = draft.endDate, !Calendar.current.isDate(start, inSameDayAs: end) else {
            return start.formatted(date: .abbreviated, time: .omitted)
        }
        return EventDateRangeFormatter.format(start: start, end: end)
    }
}
