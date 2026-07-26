//
//  PhotoQualityMetrics.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Per-photo quality signals, each normalized 0...1. Computed by `VisionEventPhotoAnalyzer`
/// (Infrastructure) from a thumbnail — see docs/sprint/SPRINT-005B.md § 11.
///
/// `faceScore` defaults to a neutral 0.5 when no face is detected — a landscape or object photo
/// isn't defective for lacking a face, so it shouldn't be penalized the way a bad portrait would.
struct PhotoQualityMetrics: Equatable {
    let sharpness: Double
    let exposure: Double
    let faceScore: Double
    let isFavorite: Bool

    /// See docs/sprint/SPRINT-005B.md § 11 — weights are a starting point, not tuned against
    /// a real library. Stored 0...100 per § 16.3's own model sketch.
    var compositeScore: Double {
        let favoriteBonus = isFavorite ? 1.0 : 0.0
        let raw = 0.35 * sharpness + 0.25 * exposure + 0.25 * faceScore + 0.15 * favoriteBonus
        return min(max(raw, 0), 1)
    }
}

/// One asset that has gone through Vision analysis and near-duplicate clustering — the
/// hand-off point from Infrastructure (`VisionEventPhotoAnalyzer`) to the pure Domain
/// selection algorithm (`EventPhotoCurationEngine`). Never carries a `PHAsset` or image bytes.
struct AnalyzedPhoto: Identifiable, Equatable {
    let assetID: String
    let sessionID: UUID?
    let creationDate: Date
    let metrics: PhotoQualityMetrics
    /// Assets that look like near-duplicates of each other share this identifier.
    /// A singleton photo gets a cluster ID that belongs to it alone.
    let similarityClusterID: String
    /// Screenshots and document/whiteboard/receipt-style photos are never the algorithm's pick
    /// within a group — see `EventPhotoCurationEngine.selectWithinGroup` and
    /// docs/sprint/SPRINT-005B-TODO.md item 7. Still shown (unselected) in the curated grid; a
    /// user can always select one manually if they actually want it.
    let isScreenshot: Bool
    let isDocument: Bool

    init(
        assetID: String,
        sessionID: UUID?,
        creationDate: Date,
        metrics: PhotoQualityMetrics,
        similarityClusterID: String,
        isScreenshot: Bool = false,
        isDocument: Bool = false
    ) {
        self.assetID = assetID
        self.sessionID = sessionID
        self.creationDate = creationDate
        self.metrics = metrics
        self.similarityClusterID = similarityClusterID
        self.isScreenshot = isScreenshot
        self.isDocument = isDocument
    }

    var id: String { assetID }
}
