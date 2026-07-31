//
//  EventPhotoAnalyzer.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Isolates Vision/CoreGraphics analysis behind a Domain-owned protocol, same pattern as
/// `PhotoAssetProvider` for PhotoKit. See docs/sprint/SPRINT-005B.md § 9.
protocol EventPhotoAnalyzer {
    /// Analyzes one Event's photos, session by session, reporting progress as
    /// sessions complete (matches the "Đã xử lý N / M nhóm" copy in § 6, § 28).
    func analyze(
        assets: [IndexedAsset],
        sessions: [PhotoSession],
        onProgress: @escaping (_ processedSessions: Int, _ totalSessions: Int) -> Void
    ) async -> [AnalyzedPhoto]

    /// Global Duplicate Suppression (docs/sprint/SPRINT-SMART-EVENT-HIGHLIGHTS.md § 27-32) — given
    /// only the small pool of already locally-selected representatives (never the full source
    /// photo set), groups the ones that are visual duplicates of each other using the feature
    /// prints captured during the most recent `analyze(...)` call on this same instance. Returns
    /// an assetID → group-key map; an assetID with no match maps to a group containing only
    /// itself. Never re-runs Vision — purely reuses what `analyze` already computed.
    func globalDuplicateGroups(candidateAssetIDs: [String], similarityThreshold: Float) -> [String: String]
}
