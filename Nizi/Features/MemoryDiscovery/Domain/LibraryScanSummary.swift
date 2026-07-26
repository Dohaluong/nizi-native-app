//
//  LibraryScanSummary.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Aggregate counts from a one-shot metadata pass over the library.
/// Sprint 2 diagnostics only — batching/checkpointing lands with the real Library Scanner
/// in a later sprint (docs/modules/memory-discovery/ARCHITECTURE.md § 6.3).
struct LibraryScanSummary: Equatable {
    let totalCount: Int
    let photoCount: Int
    let videoCount: Int
    let withDateCount: Int
    let withGPSCount: Int
    let oldestCreationDate: Date?
    let newestCreationDate: Date?
    let scanDuration: TimeInterval
}
