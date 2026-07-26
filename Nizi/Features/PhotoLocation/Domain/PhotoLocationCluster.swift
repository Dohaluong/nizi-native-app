//
//  PhotoLocationCluster.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// A group of photo IDs whose coordinates are close enough together to share one reverse-geocode
/// call and one resolved `PhotoPlace`. Each photo ID belongs to at most one cluster.
struct PhotoLocationCluster: Identifiable, Sendable {
    let id: String
    let representativeCoordinate: PhotoCoordinate
    let photoIds: [String]
}
