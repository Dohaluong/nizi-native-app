//
//  AssetAvailabilityStatus.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// See docs/database/memory-discovery.md § 4 (md_local_asset.availability_status).
/// Assets are never hard-deleted the moment they disappear from Photos — see § 20 Data lifecycle.
enum AssetAvailabilityStatus: String, Equatable {
    case available
    case unavailable
    case deleted
    case accessRevoked
}
