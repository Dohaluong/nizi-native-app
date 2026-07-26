//
//  DiscoverEventsUseCase.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Orchestrates a full rebuild of sessions/events from the current Local Memory Index.
/// The clustering itself is pure (`EventDiscoveryEngine`) — this just wires I/O around it.
final class DiscoverEventsUseCase {
    private let assetRepository: LocalAssetRepository
    private let sessionRepository: PhotoSessionRepository
    private let eventRepository: PhotoEventRepository
    private let config: EventDiscoveryConfig

    init(
        assetRepository: LocalAssetRepository,
        sessionRepository: PhotoSessionRepository,
        eventRepository: PhotoEventRepository,
        config: EventDiscoveryConfig = .default
    ) {
        self.assetRepository = assetRepository
        self.sessionRepository = sessionRepository
        self.eventRepository = eventRepository
        self.config = config
    }

    @discardableResult
    func execute() async throws -> [PhotoEvent] {
        let assets = try await assetRepository.fetchClusterableAssets()
        let result = EventDiscoveryEngine.discover(from: assets, config: config)

        try await sessionRepository.replaceRebuildableSessions(result.sessions)
        try await eventRepository.replaceRebuildableEvents(result.events)

        NiziLogger.discovery.info("event_discovery_completed sessions=\(result.sessions.count, privacy: .public) events=\(result.events.count, privacy: .public)")

        return try await eventRepository.fetchEvents(sortedBy: .scoreDescending)
    }
}
