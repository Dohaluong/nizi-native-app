//
//  EventBoundaryEvaluating.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// Decides whether two consecutive `PhotoSession`s belong to the same `PhotoEvent` — never a
/// single threshold, always a weighted combination of signals (SPEC § 2/§ 14).
protocol EventBoundaryEvaluating {
    func evaluate(
        previous: PhotoSession,
        next: PhotoSession,
        context: EventBoundaryContext
    ) -> EventBoundaryDecision
}

/// Deterministic, config-driven signal scoring. Tier values are calibrated against SPEC § 38's
/// own worked examples (a 42 min / 850 m / same-cluster pair totalling +1.75 → MERGE; a 16 h /
/// 322 km / return-home pair totalling -2.75 → hard SPLIT) — not tuned against a real library yet
/// (that's the sprint's own § 57 follow-up, done on-device with the new Diagnostics screens).
struct DefaultEventBoundaryEvaluator: EventBoundaryEvaluating {
    let config: EventDiscoveryConfig

    init(config: EventDiscoveryConfig = .default) {
        self.config = config
    }

    func evaluate(
        previous: PhotoSession,
        next: PhotoSession,
        context: EventBoundaryContext
    ) -> EventBoundaryDecision {
        let gapHours = next.startDate.timeIntervalSince(previous.endDate) / 3600

        let timeSignal = timeContinuitySignal(gapHours: gapHours)

        let distanceKm: Double? = {
            guard let prevLat = previous.centerLatitude, let prevLon = previous.centerLongitude,
                  let nextLat = next.centerLatitude, let nextLon = next.centerLongitude
            else { return nil }
            return EventDiscoveryEngine.haversineDistanceKm(lat1: prevLat, lon1: prevLon, lat2: nextLat, lon2: nextLon)
        }()
        let distanceSignal = spatialContinuitySignal(distanceKm: distanceKm)

        let sameAreaSignal = sameAreaSignal(previous: previous, next: next)

        let previousContext = LocationContextResolver.resolve(
            latitude: previous.centerLatitude, longitude: previous.centerLongitude,
            home: context.home, familiarPlaces: context.familiarPlaces, config: config
        )
        let nextContext = LocationContextResolver.resolve(
            latitude: next.centerLatitude, longitude: next.centerLongitude,
            home: context.home, familiarPlaces: context.familiarPlaces, config: config
        )
        let awaySignal = awayFromHomeSignal(nextContext: nextContext)
        let returnHomeSignal = returnHomeSignal(previousContext: previousContext, nextContext: nextContext)

        let dayBoundarySignal = dayBoundarySignal(previous: previous, next: next)

        let reasons = [timeSignal, distanceSignal, sameAreaSignal, awaySignal, returnHomeSignal, dayBoundarySignal]
        let score = reasons.reduce(0) { $0 + $1.contribution }

        // § 20 — only the signal combination fully available without I/O (time + distance +
        // Home context); the "country changed" variant needs reverse-geocoding, deferred to the
        // Application-layer Trip/Travel classification pass.
        let isHardBoundary = gapHours > config.hardBoundaryTimeGapHours
            && (distanceKm ?? 0) > config.hardBoundaryDistanceKm
            && previousContext != .home
            && nextContext == .home

        let effectiveThreshold = config.eventBoundaryMergeThreshold
            + config.eventDurationThresholdPenaltyPerDay * (context.currentEventDurationHours / 24)

        let action: BoundaryAction = isHardBoundary
            ? .split
            : (score >= effectiveThreshold ? .merge : .split)

        return EventBoundaryDecision(action: action, score: score, isHardBoundary: isHardBoundary, reasons: reasons)
    }

    // MARK: - Signals

    /// SPEC § 17 tiers, adapted to the § 38 example's magnitudes.
    private func timeContinuitySignal(gapHours: Double) -> BoundarySignalResult {
        let gapMinutes = gapHours * 60
        let contribution: Double
        switch true {
        case gapMinutes <= 10: contribution = 0.90
        case gapMinutes <= 60: contribution = 0.70
        case gapHours <= 3: contribution = 0.40
        case gapHours <= 8: contribution = 0.10
        case gapHours <= 16: contribution = -0.30
        default: contribution = -0.65
        }

        let detail = gapMinutes < 60
            ? String(format: "%.0f min", gapMinutes)
            : String(format: "%.1f h", gapHours)
        return BoundarySignalResult(name: "Time gap", detail: detail, contribution: contribution)
    }

    /// SPEC § 18 tiers, adapted to the § 38 example's magnitudes.
    private func spatialContinuitySignal(distanceKm: Double?) -> BoundarySignalResult {
        guard let distanceKm else {
            return BoundarySignalResult(name: "Distance", detail: "unknown", contribution: 0)
        }
        let contribution: Double
        switch true {
        case distanceKm < 0.2: contribution = 0.60
        case distanceKm < 2: contribution = 0.45
        case distanceKm < 20: contribution = 0.15
        case distanceKm < 100: contribution = -0.20
        default: contribution = -0.80
        }

        let detail = distanceKm < 1
            ? String(format: "%.0f m", distanceKm * 1000)
            : String(format: "%.0f km", distanceKm)
        return BoundarySignalResult(name: "Distance", detail: detail, contribution: contribution)
    }

    private func sameAreaSignal(previous: PhotoSession, next: PhotoSession) -> BoundarySignalResult {
        let same = previous.geoCell != nil && previous.geoCell == next.geoCell
        return BoundarySignalResult(name: "Same cluster", detail: same ? "YES" : "NO", contribution: same ? 0.35 : 0)
    }

    private func awayFromHomeSignal(nextContext: LocationContext) -> BoundarySignalResult {
        let isAway = nextContext == .away
        return BoundarySignalResult(name: "Away from home", detail: isAway ? "YES" : "NO", contribution: isAway ? 0.10 : 0)
    }

    /// The single strongest split-favoring signal (SPEC § 19: "AWAY → HOME là signal rất mạnh").
    private func returnHomeSignal(previousContext: LocationContext, nextContext: LocationContext) -> BoundarySignalResult {
        let isReturn = previousContext != .home && nextContext == .home
        return BoundarySignalResult(name: "Return home", detail: isReturn ? "YES" : "NO", contribution: isReturn ? -1.00 : 0)
    }

    private func dayBoundarySignal(previous: PhotoSession, next: PhotoSession) -> BoundarySignalResult {
        let crossed = !Calendar.current.isDate(previous.endDate, inSameDayAs: next.startDate)
        return BoundarySignalResult(name: "Day boundary", detail: crossed ? "YES" : "NO", contribution: crossed ? -0.15 : 0)
    }
}
