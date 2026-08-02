//
//  FastEventQualityService.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation

/// Cheap, local-only Event triage folded into the same pure pass `EventDiscoveryEngine.discover`
/// already runs (docs/sprint/SPRINT-FAST-EVENT-QUALITY.md § 1/§ 4) — no Vision, no thumbnail
/// loads, no network, O(events). Decides *visibility*, never deletes/merges/rebuilds an Event
/// (§ 9). Deliberately a separate concern from `EventDiscoveryEngine.computeScore`/`PhotoEvent
/// .score` (§ 2): that score is about discovery confidence, this is about "is this cluster worth
/// showing by default."
///
/// Only ever fed *unclassified* `PhotoTrip`s (membership/`overnightCount`/departure-return flags,
/// all already computed by the pure `TripDiscoveryEngine` pass) — never `trip.classification`,
/// which needs reverse-geocoding. Country-aware trip tiers ("international"/"domestic") from § 10
/// are intentionally not implemented: they'd require sequencing this after geocoding, which
/// directly conflicts with § 1's "không cần internet"/"không làm tăng đáng kể thời gian scan" and
/// § 20's explicit "Không: ... Reverse Geocode." A flat trip-membership bonus plus a multi-day
/// kicker (from `overnightCount`, already known pre-classification) covers the spec's intent
/// without that dependency.
enum FastEventQualityService {
    struct Result {
        let event: PhotoEvent
        /// Diagnostics-only — never persisted (only `event.eventQualityScore`/`eventVisibility` are).
        let trace: EventQualityTrace
    }

    static func classify(
        events: [PhotoEvent],
        assetsByID: [String: IndexedAsset],
        trips: [PhotoTrip],
        home: HomeAnchor?,
        familiarPlaces: [FamiliarPlace],
        config: EventDiscoveryConfig = .default
    ) -> [Result] {
        var tripByEventID: [UUID: PhotoTrip] = [:]
        for trip in trips {
            for eventID in trip.eventIDs {
                tripByEventID[eventID] = trip
            }
        }

        return events.map { event in
            classify(
                event: event,
                assets: event.assetIDs.compactMap { assetsByID[$0] },
                trip: tripByEventID[event.id],
                home: home,
                familiarPlaces: familiarPlaces,
                config: config
            )
        }
    }

    private static func classify(
        event: PhotoEvent,
        assets: [IndexedAsset],
        trip: PhotoTrip?,
        home: HomeAnchor?,
        familiarPlaces: [FamiliarPlace],
        config: EventDiscoveryConfig
    ) -> Result {
        var total = config.eventQualityBaseScore
        var reasons: [EventQualitySignalResult] = []

        func add(_ name: String, _ detail: String, _ contribution: Double) {
            total += contribution
            reasons.append(EventQualitySignalResult(name: name, detail: detail, contribution: contribution))
        }

        let assetCount = assets.count
        let favoriteCount = assets.filter(\.isFavorite).count
        let durationHours = event.endDate.timeIntervalSince(event.startDate) / 3600

        // 1. Photo count — soft penalty only, never a hard reject (§ 10: "3 ảnh vẫn có thể là Event tốt").
        if assetCount < config.eventQualityLowAssetCountThreshold {
            add("Photo Count", "\(assetCount) photos", -config.eventQualityLowAssetCountPenalty)
        } else {
            add("Photo Count", "\(assetCount) photos", 0)
        }

        // 2. Favorite — strongest positive signal.
        if favoriteCount > 0 {
            add("Favorite", "\(favoriteCount) favorited", config.eventQualityFavoriteBonus)
        } else {
            add("Favorite", "none", 0)
        }

        // 3. Duration — soft penalty if very short; short ≠ garbage, so no bonus tier either.
        if durationHours < config.eventQualityShortDurationHoursThreshold {
            add("Duration", String(format: "%.1fh", durationHours), -config.eventQualityShortDurationPenalty)
        } else {
            add("Duration", String(format: "%.1fh", durationHours), 0)
        }

        // 4. Moment count — a single, undifferentiated burst scores lower than an Event that
        // visibly moved through several distinct moments.
        let moments = momentCount(assets: assets, config: config)
        if moments <= 1 {
            add("Moment Count", "\(moments) moment", -config.eventQualitySingleMomentPenalty)
        } else if moments >= config.eventQualityManyMomentsThreshold {
            add("Moment Count", "\(moments) moments", config.eventQualityManyMomentsBonus)
        } else {
            add("Moment Count", "\(moments) moments", 0)
        }

        // 5. Session diversity — several small sessions merged into one Event is itself a signal
        // this was a real, spread-out occasion rather than one incidental burst.
        if event.sessionCount >= config.eventQualityManySessionsThreshold {
            add("Session Diversity", "\(event.sessionCount) sessions", config.eventQualitySessionDiversityBonus)
        } else {
            add("Session Diversity", "\(event.sessionCount) sessions", 0)
        }

        // 6. Screenshot ratio — strong penalty; already-available metadata, no Vision needed.
        let screenshotRatio = assetCount > 0 ? Double(assets.filter(\.isScreenshot).count) / Double(assetCount) : 0
        if screenshotRatio >= config.eventQualityScreenshotRatioThreshold {
            add("Screenshot Ratio", String(format: "%.0f%%", screenshotRatio * 100), -config.eventQualityScreenshotPenalty)
        } else {
            add("Screenshot Ratio", String(format: "%.0f%%", screenshotRatio * 100), 0)
        }

        // 7. GPS — small bonus when present; absence is neutral, never a penalty (§ 10 explicit).
        let representativeCoordinate = averageCoordinate(of: assets)
        if representativeCoordinate != nil {
            add("GPS", "present", config.eventQualityGPSBonus)
        } else {
            add("GPS", "absent", 0)
        }

        // 8. Trip involvement — membership only (pre-classification), plus a multi-day kicker.
        if let trip {
            let isMultiDay = trip.travelContext.overnightCount >= config.eventQualityMultiDayTripOvernightThreshold
            let contribution = config.eventQualityTripMembershipBonus + (isMultiDay ? config.eventQualityMultiDayTripBonus : 0)
            add("Trip", isMultiDay ? "multi-day trip" : "day trip", contribution)
        } else {
            add("Trip", "not part of a trip", 0)
        }

        // 9. Home context — only the narrow "very few + very short + at Home" case; never treat
        // every Home Event as noise (§ 10: "Sinh nhật ở nhà vẫn là Event tốt").
        let isAtHome = representativeCoordinate.map {
            LocationContextResolver.resolve(
                latitude: $0.latitude, longitude: $0.longitude,
                home: home, familiarPlaces: familiarPlaces, config: config
            ) == .home
        } ?? false
        let isLowSignal = assetCount < config.eventQualityLowAssetCountThreshold
            && durationHours < config.eventQualityShortDurationHoursThreshold
        if isAtHome, isLowSignal {
            add("Home Context", "low-signal, at home", -config.eventQualityHomeContextPenalty)
        } else {
            add("Home Context", isAtHome ? "at home" : "not at home", 0)
        }

        let score = min(max(total, 0), 1)
        let visibility: EventVisibility = score >= config.eventQualityNormalThreshold ? .normal
            : score >= config.eventQualityLowValueThreshold ? .lowValue
            : .hiddenNoise

        var scoredEvent = event
        scoredEvent.eventQualityScore = score
        scoredEvent.eventVisibility = visibility

        return Result(
            event: scoredEvent,
            trace: EventQualityTrace(eventID: event.id, score: score, visibility: visibility, reasons: reasons)
        )
    }

    /// Independent of `EventPhotoCurationEngine`'s Vision-coupled `splitIntoMoments`/
    /// `momentGroupMaxGapSeconds` (§ 11/§ 12 forbid depending on Deep Curation/Vision) — operates
    /// on plain `IndexedAsset.creationDate` only.
    private static func momentCount(assets: [IndexedAsset], config: EventDiscoveryConfig) -> Int {
        guard !assets.isEmpty else { return 0 }
        let sorted = assets.map(\.creationDate).sorted()
        var count = 1
        for (previous, next) in zip(sorted, sorted.dropFirst()) {
            if next.timeIntervalSince(previous) > config.eventQualityMomentGapSeconds { count += 1 }
        }
        return count
    }

    private static func averageCoordinate(of assets: [IndexedAsset]) -> (latitude: Double, longitude: Double)? {
        let located = assets.filter { $0.latitude != nil && $0.longitude != nil }
        guard !located.isEmpty else { return nil }
        let latitude = located.map { $0.latitude! }.reduce(0, +) / Double(located.count)
        let longitude = located.map { $0.longitude! }.reduce(0, +) / Double(located.count)
        return (latitude, longitude)
    }
}
