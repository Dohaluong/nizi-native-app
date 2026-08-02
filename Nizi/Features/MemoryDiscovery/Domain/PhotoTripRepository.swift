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
    /// Lazy, on-open place re-resolution (`TripDetailView`) — updates just the two place fields
    /// on an already-persisted trip, without touching anything else about it.
    func setTripPlace(tripID: UUID, place: EventPlace?) async throws
}
