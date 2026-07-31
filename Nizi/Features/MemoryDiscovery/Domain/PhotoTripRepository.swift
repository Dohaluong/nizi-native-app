//
//  PhotoTripRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// Trips are wholesale-replaced on every rebuild, same as `PhotoSessionRepository` — there is no
/// "accepted" trip status to protect (yet) the way `PhotoEventRepository` protects committed Events.
protocol PhotoTripRepository {
    func replaceRebuildableTrips(_ trips: [PhotoTrip]) async throws
    func fetchTrips() async throws -> [PhotoTrip]
}
