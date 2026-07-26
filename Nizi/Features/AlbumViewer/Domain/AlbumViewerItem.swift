//
//  AlbumViewerItem.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Which side of its Spread a Page is — `AlbumDraftSpread.leftPage`/`rightPage` already
/// guarantees this ordering as a domain invariant, so this only needs to exist at the
/// Presentation layer (docs/specs/ADDENDUM-001.md § 5), never added to the persisted JSON.
enum AlbumSpreadPagePosition: String, Codable, Hashable, Sendable {
    case left
    case right
}

/// One flattened Page, with enough context to find its "facing" Page (same Spread, other side)
/// for swap/remove-Spread operations without the Viewer ever showing two Pages at once
/// (docs/specs/ADDENDUM-001.md § 5, § 15).
struct AlbumViewerPage: Identifiable, Hashable {
    let id: String
    let page: AlbumDraftPage
    let pageNumber: Int
    let totalPageCount: Int
    let spreadId: String
    let spreadIndex: Int
    let positionInSpread: AlbumSpreadPagePosition
}

/// The single-page iPhone Viewer's data source (docs/specs/ADDENDUM-001.md § 2, § 4) — Cover
/// first, then every Page in order, never two Pages combined into one item. Built fresh from
/// `AlbumDraft` by `AlbumViewerItemBuilding` each time the Draft changes; never persisted itself
/// (§ 3: "Không sao chép hoặc persistence danh sách đã flatten").
enum AlbumViewerItem: Identifiable, Hashable {
    case cover(AlbumCoverConfiguration)
    case page(AlbumViewerPage)

    var id: String {
        switch self {
        case .cover: "cover"
        case let .page(page): page.id
        }
    }
}
