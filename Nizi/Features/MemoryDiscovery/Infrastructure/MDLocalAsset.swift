//
//  MDLocalAsset.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation
import SwiftData

/// SwiftData schema v1 — see docs/database/memory-discovery.md § 4 and § 19.
/// Only Infrastructure touches this type; Domain/Application only ever see `PhotoAssetRecord`.
@Model
final class MDLocalAsset {
    @Attribute(.unique) var assetLocalIdentifier: String
    var creationDate: Date?
    var modificationDate: Date?
    var mediaType: String
    var pixelWidth: Int
    var pixelHeight: Int
    var duration: Double
    var latitude: Double?
    var longitude: Double?
    var favorite: Bool
    var hidden: Bool
    var screenshot: Bool
    var burstIdentifier: String?
    var sourceType: String
    var availabilityStatus: String
    var discoveryStatus: String
    var qualityScore: Double?
    var analysisVersion: Int
    var lastSeenAt: Date
    var createdAt: Date
    var updatedAt: Date

    init(record: PhotoAssetRecord, now: Date) {
        assetLocalIdentifier = record.id
        creationDate = record.creationDate
        modificationDate = record.modificationDate
        mediaType = record.mediaType.rawValue
        pixelWidth = record.pixelWidth
        pixelHeight = record.pixelHeight
        duration = record.duration
        latitude = record.latitude
        longitude = record.longitude
        favorite = record.isFavorite
        hidden = record.isHidden
        screenshot = record.isScreenshot
        burstIdentifier = record.burstIdentifier
        sourceType = record.sourceType.rawValue
        availabilityStatus = AssetAvailabilityStatus.available.rawValue
        discoveryStatus = AssetDiscoveryStatus.indexed.rawValue
        qualityScore = nil
        analysisVersion = 0
        lastSeenAt = now
        createdAt = now
        updatedAt = now
    }

    func apply(_ record: PhotoAssetRecord, now: Date) {
        creationDate = record.creationDate
        modificationDate = record.modificationDate
        mediaType = record.mediaType.rawValue
        pixelWidth = record.pixelWidth
        pixelHeight = record.pixelHeight
        duration = record.duration
        latitude = record.latitude
        longitude = record.longitude
        favorite = record.isFavorite
        hidden = record.isHidden
        screenshot = record.isScreenshot
        burstIdentifier = record.burstIdentifier
        sourceType = record.sourceType.rawValue
        // A re-scanned asset is by definition available again.
        availabilityStatus = AssetAvailabilityStatus.available.rawValue
        lastSeenAt = now
        updatedAt = now
    }
}
