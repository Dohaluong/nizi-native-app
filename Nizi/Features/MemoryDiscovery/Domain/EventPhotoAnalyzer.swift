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
}
