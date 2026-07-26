//
//  PhotoCurationItem.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// One photo's place in a curation group — see docs/sprint/SPRINT-005B.md § 16.3.
/// `isSuggested` is the algorithm's original call and never changes after the group is
/// created; `isSelected`/`selectionSource` track what's actually chosen, which the user
/// can override without disturbing `isSuggested`.
struct PhotoCurationItem: Identifiable, Equatable {
    let id: UUID
    /// `var` — Photo Editor's Event "save as new asset" flow (`PhotoAssetExporting`) exports a
    /// brand-new `PHAsset` for whichever photo was just edited, and
    /// `EventCurationRepository.updateItemAsset` swaps this item's identifier over to it.
    var assetID: String
    var sortOrder: Int
    /// 0...100 — see `PhotoQualityMetrics.compositeScore`.
    let qualityScore: Int
    let similarityClusterID: String
    let isSuggested: Bool
    var isSelected: Bool
    var selectionSource: SelectionSource
}
