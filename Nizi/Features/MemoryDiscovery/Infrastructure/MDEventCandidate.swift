//
//  MDEventCandidate.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation
import SwiftData

/// SwiftData schema — see docs/database/memory-discovery.md § 8.
/// `sessionIdentifiers`/`assetIdentifiers` are materialized arrays rather than join tables,
/// same reasoning as `MDPhotoSession`. `discoveryReasons` is split into two parallel arrays
/// (kind/text) instead of a nested Codable array — simpler and safer against SwiftData's
/// array-of-struct storage quirks than it's worth for four short strings.
@Model
final class MDEventCandidate {
    @Attribute(.unique) var candidateID: UUID
    var titleSuggestion: String
    var startDate: Date
    var endDate: Date
    var primaryLocationLabel: String?
    var eventType: String
    var score: Double
    var status: String
    var sessionIdentifiers: [UUID]
    var assetIdentifiers: [String]
    var coverAssetID: String?
    var discoveryReasonKinds: [String]
    var discoveryReasonTexts: [String]
    var algorithmVersion: Int
    var createdAt: Date
    var updatedAt: Date

    init(event: PhotoEvent) {
        candidateID = event.id
        titleSuggestion = event.titleSuggestion
        startDate = event.startDate
        endDate = event.endDate
        primaryLocationLabel = event.primaryLocationLabel
        eventType = event.eventType.rawValue
        score = event.score
        status = event.status.rawValue
        sessionIdentifiers = event.sessionIDs
        assetIdentifiers = event.assetIDs
        coverAssetID = event.coverAssetID
        discoveryReasonKinds = event.discoveryReasons.map { $0.kind.rawValue }
        discoveryReasonTexts = event.discoveryReasons.map(\.text)
        algorithmVersion = event.algorithmVersion
        createdAt = event.createdAt
        updatedAt = event.updatedAt
    }
}

extension PhotoEvent {
    init(model: MDEventCandidate) {
        let reasons = zip(model.discoveryReasonKinds, model.discoveryReasonTexts).map { kind, text in
            DiscoveryReason(kind: DiscoveryReasonKind(rawValue: kind) ?? .assetCountOverDuration, text: text)
        }
        self.init(
            id: model.candidateID,
            titleSuggestion: model.titleSuggestion,
            startDate: model.startDate,
            endDate: model.endDate,
            primaryLocationLabel: model.primaryLocationLabel,
            eventType: EventType(rawValue: model.eventType) ?? .unknown,
            score: model.score,
            status: PhotoEventStatus(rawValue: model.status) ?? .new,
            sessionIDs: model.sessionIdentifiers,
            assetIDs: model.assetIdentifiers,
            coverAssetID: model.coverAssetID,
            discoveryReasons: reasons,
            algorithmVersion: model.algorithmVersion,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }
}
