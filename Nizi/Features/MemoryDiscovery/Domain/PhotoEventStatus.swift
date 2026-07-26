//
//  PhotoEventStatus.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// See docs/modules/memory-discovery/ARCHITECTURE.md § 7 and ADR-MD-006.
/// Sprint 4 only ever writes `.new`; the rest exist so later sprints (Event Review,
/// Album Draft) don't need a schema change. `.accepted`/`.convertedToAlbum` are the two
/// statuses a rebuild must never silently discard — see `PhotoEventRepository`.
enum PhotoEventStatus: String, Equatable {
    case new
    case viewed
    case accepted
    case dismissed
    case snoozed
    case merged
    case convertedToAlbum
}
