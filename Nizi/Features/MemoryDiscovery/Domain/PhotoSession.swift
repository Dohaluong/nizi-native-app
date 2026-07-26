//
//  PhotoSession.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// A tight cluster of assets taken close together in time (and, if available, in space).
/// See docs/database/memory-discovery.md § 6 — asset membership is materialized directly
/// as `assetIDs` rather than a separate join table (SwiftData stores the array natively).
struct PhotoSession: Identifiable, Equatable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let centerLatitude: Double?
    let centerLongitude: Double?
    let geoCell: String?
    let assetIDs: [String]
    /// Assets per hour — used both for merge/scoring decisions and surfaced for debugging.
    let densityScore: Double

    var assetCount: Int { assetIDs.count }
}
