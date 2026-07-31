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
    /// the Cover. `previousItems` (the item list from just before whatever change happened) is
    /// what makes "closest remaining" real — without it there's no way to know *where* the
    /// removed item used to sit, so this used to just always land on the very last item (§ user
    /// report — "xoá trang xong thay vì chuyển đến trang tiếp theo thì app chuyển đến trang cuối
    /// cùng"). Pages are stored in Viewer order, so clamping the removed item's old ordinal
    /// position into the new list lands on whatever slid up to take its place — the Page that
    /// used to come right after it, or the previous Page if the removed one was last.
    func resolved(against items: [AlbumViewerItem], previousItems: [AlbumViewerItem] = []) -> AlbumViewerSelection? {
        guard !items.isEmpty else { return nil }
        if items.contains(where: { $0.id == itemId }) {
            return self
        }
        if let oldIndex = previousItems.firstIndex(where: { $0.id == itemId }) {
            let clampedIndex = min(oldIndex, items.count - 1)
            return AlbumViewerSelection(itemId: items[clampedIndex].id)
        }
        return AlbumViewerSelection(itemId: items.last?.id ?? items[0].id)
    }
}
