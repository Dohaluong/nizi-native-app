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
        // Unify Home Source (SPRINT-NEXT § 1-4): read back whatever Home is already persisted
        // (confirmed or previously-inferred) so `discover` can prefer it over a brand-new guess.
        let persistedHome = try await locationIntelligenceRepository.fetchHome()
        // This is CPU-bound work over the entire library (location clustering alone can visit
        // 100k+ assets). `FirstExperienceCoordinator` is MainActor-bound for UI state, so doing
        // it inline made the app appear frozen immediately after index reached 100%.
        let result = await Task.detached(priority: .userInitiated) {
            EventDiscoveryEngine.discover(from: assets, config: config, preferredHome: persistedHome)
        }.value

        try await sessionRepository.replaceRebuildableSessions(result.sessions)
        try await locationIntelligenceRepository.replaceLocationIntelligence(
            clusters: result.locationClusters, home: result.home, familiarPlaces: result.familiarPlaces
        )

        let classifiedTrips = await travelClassificationService.classify(trips: result.trips, home: result.home)
        try await tripRepository.replaceRebuildableTrips(classifiedTrips)

        // Memory Potential (SPRINT-NEXT § 10-14) needs `classifiedTrips` (international/domestic
        // already resolved) — this is exactly why it can't fold into the pure `discover()` pass
        // above, same reason trip classification itself can't. Events are persisted once, here,
        // after this runs — no second write pass.
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let memoryResults = MemoryPotentialEvaluator.evaluate(
            events: result.events, trips: classifiedTrips, assetsByID: assetsByID,
            home: result.home, familiarPlaces: result.familiarPlaces, config: config
        )
        try await eventRepository.replaceRebuildableEvents(memoryResults.map(\.event))

        NiziLogger.discovery.info("event_discovery_completed sessions=\(result.sessions.count, privacy: .public) events=\(result.events.count, privacy: .public) trips=\(classifiedTrips.count, privacy: .public) home=\(result.home != nil, privacy: .public)")

        return try await eventRepository.fetchEvents(sortedBy: .scoreDescending)
    }
}
