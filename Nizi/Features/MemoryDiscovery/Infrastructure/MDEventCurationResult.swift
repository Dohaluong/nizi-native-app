//
//  MDEventCurationResult.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation
import SwiftData

/// SwiftData schema — see docs/sprint/SPRINT-005B.md § 16. Three flat tables (result/group/item)
/// linked by plain UUID fields rather than `@Relationship`, matching how `MDEventCandidate` and
/// `MDPhotoSession` already avoid SwiftData relationships elsewhere in this module.
///
/// One row per Event — additive migration, existing events simply have no row
/// here yet, which reads as `.notStarted`. See § 36.
@Model
final class MDEventCurationResult {
    @Attribute(.unique) var eventCandidateID: UUID
    var status: String
    var algorithmVersion: Int
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var sourceAssetCount: Int
    /// Additive field — defaulted for lightweight migration, same convention as
    /// `MDHomeAnchor.source`. Existing rows read back as `""`, which never equals a freshly
    /// computed fingerprint, so they simply invalidate on next open rather than crash or migrate.
    var sourceAssetFingerprint: String = ""
    var errorMessage: String?

    init(eventCandidateID: UUID, status: CurationStatus, algorithmVersion: Int, now: Date) {
        self.eventCandidateID = eventCandidateID
        self.status = status.rawValue
        self.algorithmVersion = algorithmVersion
        createdAt = now
        updatedAt = now
        completedAt = nil
        sourceAssetCount = 0
        sourceAssetFingerprint = ""
        errorMessage = nil
    }
}

@Model
final class MDPhotoCurationGroup {
    @Attribute(.unique) var id: UUID
    var eventCandidateID: UUID
    var sessionID: UUID?
    var startDate: Date
    var endDate: Date
    var sortOrder: Int

    init(group: PhotoCurationGroup, eventCandidateID: UUID) {
        id = group.id
        self.eventCandidateID = eventCandidateID
        sessionID = group.sessionID
        startDate = group.startDate
        endDate = group.endDate
        sortOrder = group.sortOrder
    }
}

@Model
final class MDPhotoCurationItem {
    @Attribute(.unique) var id: UUID
    var groupID: UUID
    var eventCandidateID: UUID
    var assetLocalIdentifier: String
    var sortOrder: Int
    var qualityScore: Int
    var similarityClusterIdentifier: String
    var isSuggested: Bool
    var isSelected: Bool
    var selectionSource: String
    /// Additive field — defaulted for lightweight migration. `nil` on any row written before this
    /// sprint (or by the algorithm whenever an item is actually selected/still eligible).
    var rejectionReason: String?

    init(item: PhotoCurationItem, groupID: UUID, eventCandidateID: UUID) {
        id = item.id
        self.groupID = groupID
        self.eventCandidateID = eventCandidateID
        assetLocalIdentifier = item.assetID
        sortOrder = item.sortOrder
        qualityScore = item.qualityScore
        similarityClusterIdentifier = item.similarityClusterID
        isSuggested = item.isSuggested
        isSelected = item.isSelected
        selectionSource = item.selectionSource.rawValue
        rejectionReason = item.rejectionReason?.rawValue
    }
}
