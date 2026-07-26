//
//  AssetDiscoveryStatus.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// See docs/database/memory-discovery.md § 4 (md_local_asset.discovery_status).
/// `.clustered` and `.ignored` are set by later sprints (Event Discovery) — Sprint 3 only ever writes `.indexed`.
enum AssetDiscoveryStatus: String, Equatable {
    case new
    case indexed
    case clustered
    case ignored
    case error
}
