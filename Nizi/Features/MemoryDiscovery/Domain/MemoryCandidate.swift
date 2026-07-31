//
//  MemoryCandidate.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// A `PhotoEvent` that's been scored and curated well enough to show a user as their "First
/// Memory" — the product-level result the onboarding flow builds toward. See
/// docs/sprint/SPRINT-FIRST-MEMORY-EXPERIENCE.md § 6/§ 7: deliberately not an `AlbumDraft` —
/// Memory is a viewing experience, Album/Photobook is a separate, optional output built later.
struct MemoryCandidate: Identifiable, Equatable {
    let id: UUID
    let eventID: UUID
    var title: String
    var subtitle: String?
    let startDate: Date
    let endDate: Date
    var placeName: String?
    var coverAssetID: String
    var selectedAssetIDs: [String]
    var totalPhotoCount: Int
    var score: Double
    var status: MemoryStatus
    let createdAt: Date
    var updatedAt: Date
}
