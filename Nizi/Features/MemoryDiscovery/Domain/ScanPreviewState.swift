//
//  ScanPreviewState.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// One candidate for the Memory Journey's small photo row — just enough to pick a thumbnail and
/// prioritize favorites, never a full asset record (SPRINT-INITIAL-SCAN-MEMORY-JOURNEY-HOME § 7).
struct ScanPreviewCandidate: Identifiable, Equatable {
    var id: String { assetID }
    let assetID: String
    let isFavorite: Bool
}

/// What `UserScanProgressView` renders per scan-progress tick. `currentYear` is derived from
/// whatever `ScanCheckpoint.lastAssetCreationDate` the scanner already reports — no new PhotoKit
/// work needed for that part (§ 5).
struct ScanPreviewState: Equatable {
    let currentYear: Int?
    let candidates: [ScanPreviewCandidate]

    static let empty = ScanPreviewState(currentYear: nil, candidates: [])
}

struct ScanPreviewConfig {
    var maxCandidates: Int = 8
    static let `default` = ScanPreviewConfig()
}
