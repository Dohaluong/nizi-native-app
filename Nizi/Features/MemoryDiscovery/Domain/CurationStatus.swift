//
//  CurationStatus.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Per-Event curation state — see docs/sprint/SPRINT-005B.md § 5.
/// Old events that predate Sprint 005B have no row at all, which reads as `.notStarted`.
enum CurationStatus: String, Equatable {
    case notStarted
    case processing
    case completed
    case failed
    case outdated
}
