//
//  LocationIntelligenceRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// Persists `LocationIntelligenceEngine.Result` — wholesale-replaced on every rebuild, same
/// idempotency strategy as `PhotoSessionRepository.replaceRebuildableSessions`. **Exception**:
/// `replaceLocationIntelligence` must never overwrite a `HomeAnchor` whose `source ==
/// .userConfirmed` — that's the one piece of "committed" state this module now has (SPRINT-
/// INITIAL-SCAN-MEMORY-JOURNEY-HOME § 21). `confirmUserHome` is the dedicated write path for it.
protocol LocationIntelligenceRepository {
    func replaceLocationIntelligence(clusters: [LocationCluster], home: HomeAnchor?, familiarPlaces: [FamiliarPlace]) async throws
    func confirmUserHome(_ home: HomeAnchor) async throws
    func fetchHome() async throws -> HomeAnchor?
    func fetchFamiliarPlaces() async throws -> [FamiliarPlace]
    func fetchLocationClusters() async throws -> [LocationCluster]
}
