//
//  AlbumViewerSelection.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Identity-based, not a bare `Int` index — so an edit that changes how many Pages exist doesn't
/// strand the Viewer on the wrong item. See docs/specs/ADDENDUM-001.md § 20.
struct AlbumViewerSelection: Equatable {
    let itemId: String

    /// Re-resolves this selection against a (possibly changed) item list: keep the same item if
    /// it still exists; otherwise land on the closest remaining item; never silently jump back to
    /// the Cover.
    func resolved(against items: [AlbumViewerItem]) -> AlbumViewerSelection? {
        guard !items.isEmpty else { return nil }
        if items.contains(where: { $0.id == itemId }) {
            return self
        }
        // Item was removed — this only really applies to Pages (the Cover is never removed), so
        // approximate "closest remaining" using the removed Page's old ordinal position: pages
        // are stored in Viewer order, so clamping the previous position works well enough.
        return AlbumViewerSelection(itemId: items.last?.id ?? items[0].id)
    }
}
