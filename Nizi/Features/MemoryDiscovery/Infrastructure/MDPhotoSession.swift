//
//  MDPhotoSession.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation
import SwiftData

/// SwiftData schema — see docs/database/memory-discovery.md § 6.
/// `assetIdentifiers` is stored directly as an array rather than a separate
/// `md_session_asset` join table — SwiftData handles primitive arrays natively,
/// and nothing needs to query the join independently in Sprint 4's scope.
@Model
final class MDPhotoSession {
    @Attribute(.unique) var sessionID: UUID
    var startDate: Date
    var endDate: Date
    var centerLatitude: Double?
    var centerLongitude: Double?
    var geoCell: String?
    var assetIdentifiers: [String]
    var densityScore: Double
    var createdAt: Date

    init(session: PhotoSession, now: Date) {
        sessionID = session.id
        startDate = session.startDate
        endDate = session.endDate
        centerLatitude = session.centerLatitude
        centerLongitude = session.centerLongitude
        geoCell = session.geoCell
        assetIdentifiers = session.assetIDs
        densityScore = session.densityScore
        createdAt = now
    }
}

extension PhotoSession {
    init(model: MDPhotoSession) {
        self.init(
            id: model.sessionID,
            startDate: model.startDate,
            endDate: model.endDate,
            centerLatitude: model.centerLatitude,
            centerLongitude: model.centerLongitude,
            geoCell: model.geoCell,
            assetIDs: model.assetIdentifiers,
            densityScore: model.densityScore
        )
    }
}
