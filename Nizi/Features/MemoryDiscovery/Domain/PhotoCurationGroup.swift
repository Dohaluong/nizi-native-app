//
//  PhotoCurationGroup.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// A "moment" within a curated event — consecutive photos taken within
/// `EventPhotoCurationEngine.Configuration.momentGroupMaxGapSeconds` of each other (default 60s),
/// never spanning a bigger gap even within the same underlying `PhotoSession`. See
/// docs/sprint/SPRINT-005B.md § 16.2, § 24 and docs/sprint/SPRINT-005B-TODO.md item 5.
/// Finer near-duplicate grouping lives one level down, as `PhotoCurationItem.similarityClusterID`
/// — deliberately not a further-nested UI card per similarity cluster.
struct PhotoCurationGroup: Identifiable, Equatable {
    let id: UUID
    let sessionID: UUID?
    let startDate: Date
    let endDate: Date
    var sortOrder: Int
    var items: [PhotoCurationItem]

    var assetCount: Int { items.count }
    var suggestedCount: Int { items.filter(\.isSelected).count }
}
