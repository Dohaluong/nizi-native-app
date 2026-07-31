//
//  MDMemoryCandidate.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation
import SwiftData

/// SwiftData schema for `MemoryCandidate`. Flat/materialized fields, same convention as
/// `MDEventCandidate` — `selectedAssetIdentifiers` is a materialized array rather than a
/// join table.
@Model
final class MDMemoryCandidate {
    @Attribute(.unique) var candidateID: UUID
    var eventID: UUID
    var title: String
    var subtitle: String?
    var startDate: Date
    var endDate: Date
    var placeName: String?
    var coverAssetID: String
    var selectedAssetIdentifiers: [String]
    var totalPhotoCount: Int
    var score: Double
    var status: String
    var createdAt: Date
    var updatedAt: Date

    init(candidate: MemoryCandidate) {
        candidateID = candidate.id
        eventID = candidate.eventID
        title = candidate.title
        subtitle = candidate.subtitle
        startDate = candidate.startDate
        endDate = candidate.endDate
        placeName = candidate.placeName
        coverAssetID = candidate.coverAssetID
        selectedAssetIdentifiers = candidate.selectedAssetIDs
        totalPhotoCount = candidate.totalPhotoCount
        score = candidate.score
        status = candidate.status.rawValue
        createdAt = candidate.createdAt
        updatedAt = candidate.updatedAt
    }
}

extension MemoryCandidate {
    init(model: MDMemoryCandidate) {
        self.init(
            id: model.candidateID,
            eventID: model.eventID,
            title: model.title,
            subtitle: model.subtitle,
            startDate: model.startDate,
            endDate: model.endDate,
            placeName: model.placeName,
            coverAssetID: model.coverAssetID,
            selectedAssetIDs: model.selectedAssetIdentifiers,
            totalPhotoCount: model.totalPhotoCount,
            score: model.score,
            status: MemoryStatus(rawValue: model.status) ?? .ready,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }
}
