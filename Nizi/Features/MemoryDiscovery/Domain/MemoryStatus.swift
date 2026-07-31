//
//  MemoryStatus.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// Lifecycle of a `MemoryCandidate`. First Memory Experience (docs/sprint/
/// SPRINT-FIRST-MEMORY-EXPERIENCE.md § 6.1) only ever produces `.ready` — `.saved` and
/// `.dismissed` are reserved for the optional "Lưu Memory"/dismiss actions of a later sprint.
enum MemoryStatus: String, Equatable {
    case provisional
    case ready
    case saved
    case dismissed
}
