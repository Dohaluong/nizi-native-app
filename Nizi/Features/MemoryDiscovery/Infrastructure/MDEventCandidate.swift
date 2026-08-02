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
    var placeLatitude: Double?
    var placeLongitude: Double?
    var placeSubLocality: String?
    var placeLocality: String?
    var placeSubAdministrativeArea: String?
    var placeAdministrativeArea: String?
    var placeCountry: String?
    var placeCountryCode: String?
    var placeDisplayName: String?
    var placeResolutionState: String = EventPlaceResolutionState.unresolved.rawValue
    var placeResolvedAt: Date?
    var eventType: String
    var score: Double
    var status: String
    var isLoved: Bool = false
    var sessionIdentifiers: [UUID]
    var assetIdentifiers: [String]
    var coverAssetID: String?
    var discoveryReasonKinds: [String]
    var discoveryReasonTexts: [String]
    var algorithmVersion: Int
    var createdAt: Date
    var updatedAt: Date
    /// Additive fields for SPRINT-FAST-EVENT-QUALITY — defaulted for lightweight migration, same
    /// convention as `MDHomeAnchor.source`/`MDEventCurationResult.sourceAssetFingerprint`.
    var qualityScore: Double = 0
    var visibility: String = EventVisibility.normal.rawValue
    /// Additive fields for SPRINT-NEXT (Memory Potential) — defaulted for lightweight migration,
    /// same convention as `qualityScore`/`visibility` above.
    var isAutoMemory: Bool = false
    var autoMemoryScore: Double = 0

    init(event: PhotoEvent) {
        candidateID = event.id
        titleSuggestion = event.titleSuggestion
        startDate = event.startDate
        endDate = event.endDate
        primaryLocationLabel = event.primaryLocationLabel
        placeLatitude = event.eventPlace?.coordinate.latitude
        placeLongitude = event.eventPlace?.coordinate.longitude
        placeSubLocality = event.eventPlace?.subLocality
        placeLocality = event.eventPlace?.locality
        placeSubAdministrativeArea = event.eventPlace?.subAdministrativeArea
        placeAdministrativeArea = event.eventPlace?.administrativeArea
        placeCountry = event.eventPlace?.country
        placeCountryCode = event.eventPlace?.countryCode
        placeDisplayName = event.eventPlace?.displayName
        placeResolutionState = event.placeResolutionState.rawValue
        placeResolvedAt = event.eventPlace == nil ? nil : Date()
        eventType = event.eventType.rawValue
        score = event.score
        status = event.status.rawValue
        isLoved = event.isLoved
        sessionIdentifiers = event.sessionIDs
        assetIdentifiers = event.assetIDs
        coverAssetID = event.coverAssetID
        discoveryReasonKinds = event.discoveryReasons.map { $0.kind.rawValue }
        discoveryReasonTexts = event.discoveryReasons.map(\.text)
        algorithmVersion = event.algorithmVersion
        createdAt = event.createdAt
        updatedAt = event.updatedAt
        qualityScore = event.eventQualityScore
        visibility = event.eventVisibility.rawValue
        isAutoMemory = event.isAutoMemory
        autoMemoryScore = event.autoMemoryScore
    }
}

extension PhotoEvent {
    init(model: MDEventCandidate) {
        let reasons = zip(model.discoveryReasonKinds, model.discoveryReasonTexts).map { kind, text in
            DiscoveryReason(kind: DiscoveryReasonKind(rawValue: kind) ?? .assetCountOverDuration, text: text)
        }
        let place: EventPlace?
        if let latitude = model.placeLatitude,
           let longitude = model.placeLongitude,
           let coordinate = PhotoCoordinate(latitude: latitude, longitude: longitude) {
            place = EventPlace(
                coordinate: coordinate, subLocality: model.placeSubLocality, locality: model.placeLocality,
                subAdministrativeArea: model.placeSubAdministrativeArea, administrativeArea: model.placeAdministrativeArea, country: model.placeCountry,
                countryCode: model.placeCountryCode, displayName: model.placeDisplayName ?? ""
            )
        } else {
            place = nil
        }
        self.init(
            id: model.candidateID,
            titleSuggestion: model.titleSuggestion,
            startDate: model.startDate,
            endDate: model.endDate,
            primaryLocationLabel: model.primaryLocationLabel,
            eventPlace: place,
            placeResolutionState: EventPlaceResolutionState(rawValue: model.placeResolutionState) ?? .unresolved,
            eventType: EventType(rawValue: model.eventType) ?? .unknown,
            score: model.score,
            status: PhotoEventStatus(rawValue: model.status) ?? .new,
            isLoved: model.isLoved,
            sessionIDs: model.sessionIdentifiers,
            assetIDs: model.assetIdentifiers,
            coverAssetID: model.coverAssetID,
            discoveryReasons: reasons,
            algorithmVersion: model.algorithmVersion,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            eventQualityScore: model.qualityScore,
            eventVisibility: EventVisibility(rawValue: model.visibility) ?? .normal,
            isAutoMemory: model.isAutoMemory,
            autoMemoryScore: model.autoMemoryScore
        )
    }
}
