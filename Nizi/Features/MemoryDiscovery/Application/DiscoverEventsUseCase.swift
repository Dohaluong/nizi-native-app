//
//  DiscoverEventsUseCase.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Orchestrates a full rebuild of sessions/events/location-intelligence/trips from the current
/// Local Memory Index. The clustering itself is pure (`EventDiscoveryEngine`, which now also
/// runs Location Intelligence + Trip Discovery internally) — this just wires I/O around it and
/// runs the one I/O-dependent step the pure engine can't do itself: Trip country classification
/// (needs reverse-geocoding — see `TravelClassificationService`).
final class DiscoverEventsUseCase {
    private let assetRepository: LocalAssetRepository
    private let sessionRepository: PhotoSessionRepository
    private let eventRepository: PhotoEventRepository
    private let locationIntelligenceRepository: LocationIntelligenceRepository
    private let tripRepository: PhotoTripRepository
    private let travelClassificationService: TravelClassificationService
    private let config: EventDiscoveryConfig

    init(
        assetRepository: LocalAssetRepository,
        sessionRepository: PhotoSessionRepository,
        eventRepository: PhotoEventRepository,
        locationIntelligenceRepository: LocationIntelligenceRepository,
        tripRepository: PhotoTripRepository,
        travelClassificationService: TravelClassificationService = TravelClassificationService(),
        config: EventDiscoveryConfig = .default
    ) {
        self.assetRepository = assetRepository
        self.sessionRepository = sessionRepository
        self.eventRepository = eventRepository
        self.locationIntelligenceRepository = locationIntelligenceRepository
        self.tripRepository = tripRepository
        self.travelClassificationService = travelClassificationService
        self.config = config
    }

    @discardableResult
    func execute() async throws -> [PhotoEvent] {
        let assets = try await assetRepository.fetchClusterableAssets()
        let result = EventDiscoveryEngine.discover(from: assets, config: config)

        try await sessionRepository.replaceRebuildableSessions(result.sessions)
        try await eventRepository.replaceRebuildableEvents(result.events)
        try await locationIntelligenceRepository.replaceLocationIntelligence(
            clusters: result.locationClusters, home: result.home, familiarPlaces: result.familiarPlaces
        )

        let classifiedTrips = await travelClassificationService.classify(trips: result.trips, home: result.home)
        try await tripRepository.replaceRebuildableTrips(classifiedTrips)

        NiziLogger.discovery.info("event_discovery_completed sessions=\(result.sessions.count, privacy: .public) events=\(result.events.count, privacy: .public) trips=\(classifiedTrips.count, privacy: .public) home=\(result.home != nil, privacy: .public)")

        return try await eventRepository.fetchEvents(sortedBy: .scoreDescending)
    }
}
