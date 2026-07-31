//
//  MemoryCandidateScoring.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// "Is this Event good enough to be a user's First Memory?" — a product-level score, 0...100,
/// computed before curation runs (docs/sprint/SPRINT-FIRST-MEMORY-EXPERIENCE.md § 8/§ 9). Deliberately
/// separate from `PhotoEvent.score` (which only measures clustering cohesion for `EventDiscoveryEngine`
/// itself — see `EventDiscoveryEngine.computeScore`), even though it reuses that value as its base.
protocol MemoryCandidateScoring {
    func score(event: PhotoEvent) -> Double
}

/// Deterministic — no AI, no randomness, matches every other scoring engine in this module.
struct DefaultMemoryCandidateScoring: MemoryCandidateScoring {
    func score(event: PhotoEvent) -> Double {
        // `event.score` already folds in temporal/spatial cohesion, density, favorites, duration,
        // media diversity and a screenshot/burst noise penalty (EventDiscoveryEngine.swift:242-267)
        // — reuse it as the base rather than re-deriving the same signals, then add small
        // product-level bonuses the discovery engine itself doesn't weight.
        var value = event.score * 100

        if event.primaryLocationLabel != nil {
            value += 5
        }
        if event.assetCount >= 20 {
            value += 5
        }
        if event.discoveryReasons.contains(where: { $0.kind == .favoritesPresent }) {
            value += 5
        }

        return min(max(value, 0), 100)
    }
}

/// Centralizes the First Memory eligibility threshold — never hardcoded inline in the
/// coordinator or a view. Tunable starting point per § 9.2; not yet tuned against real data.
enum MemoryCandidateScoringConfig {
    static let firstMemoryMinimumScore: Double = 70
}
