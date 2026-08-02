//
//  MemoryPotentialSignalResult.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation

/// One evaluated Memory Potential signal — boolean, not a weighted contribution (unlike
/// `EventQualitySignalResult`), because Memory Potential's rule (SPRINT-NEXT § 13) is
/// deliberately "quality gate + at least one strong signal," not a continuous score.
struct MemoryPotentialSignalResult: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let detail: String
    let isMet: Bool
}

/// Diagnostics-only trace — never persisted (only `PhotoEvent.isAutoMemory`/`autoMemoryScore`
/// are), same "recompute for display" convention `EventQualityTrace` already established.
struct MemoryPotentialTrace: Equatable {
    let eventID: UUID
    let score: Double
    let isAutoMemory: Bool
    let reasons: [MemoryPotentialSignalResult]
}
