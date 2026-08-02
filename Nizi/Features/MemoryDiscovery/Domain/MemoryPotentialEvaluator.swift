//
//  MemoryPotentialEvaluator.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation

/// Decides which Events are special enough for Nizi to proactively surface as a "Kỷ niệm" on
/// Home, without the user ever having to ♥ them (SPRINT-NEXT § 10-14). Deliberately a gate on top
/// of Fast Event Quality, not an independent score: "clean and meaningful" (Fast Event Quality)
/// and "special enough to proactively surface" (Memory Potential) are different questions — see
/// § 11.
///
/// Requires `trips` already classified by `TravelClassificationService` (international/domestic
/// known), which is exactly why this can't fold into the same pure `EventDiscoveryEngine.discover`
/// pass Fast Event Quality uses — same reverse-geocoding-ordering constraint that already keeps
/// trip *classification* out of that pass. No Vision, no Curation, no per-event I/O beyond assets
/// already in memory — same O(events) cost class as `FastEventQualityService`.
enum MemoryPotentialEvaluator {
    struct Result {
        let event: PhotoEvent
        /// Diagnostics-only — never persisted (only `event.isAutoMemory`/`autoMemoryScore` are).
        let trace: MemoryPotentialTrace
    }

    static func evaluate(
        events: [PhotoEvent],
        trips: [PhotoTrip],
        assetsByID: [String: IndexedAsset],
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
            evaluate(
                event: event,
                assets: event.assetIDs.compactMap { assetsByID[$0] },
                trip: tripByEventID[event.id],
                home: home,
                familiarPlaces: familiarPlaces,
                config: config
            )
        }
    }

    private static func evaluate(
        event: PhotoEvent,
        assets: [IndexedAsset],
        trip: PhotoTrip?,
        home: HomeAnchor?,
        familiarPlaces: [FamiliarPlace],
        config: EventDiscoveryConfig
    ) -> Result {
        var reasons: [MemoryPotentialSignalResult] = []
        func note(_ name: String, _ detail: String, _ isMet: Bool) {
            reasons.append(MemoryPotentialSignalResult(name: name, detail: detail, isMet: isMet))
        }

        // Base gate — must be clean (Fast Event Quality) and already scoring well above the
        // ordinary "visible" bar before Memory Potential even considers a strong signal.
        let baseGateMet = event.eventVisibility != .hiddenNoise
            && event.eventQualityScore >= config.memoryPotentialQualityThreshold
        note("Quality Gate", String(format: "%.2f", event.eventQualityScore), baseGateMet)

        let favoriteCount = assets.filter(\.isFavorite).count
        let favoriteRatio = assets.isEmpty ? 0 : Double(favoriteCount) / Double(assets.count)
        let durationHours = event.endDate.timeIntervalSince(event.startDate) / 3600
        let coordinate = averageCoordinate(of: assets)

        let isInternationalTrip = trip?.classification == .internationalTrip
        note("International Trip", trip?.primaryPlaceName ?? "none", isInternationalTrip)

        let isMultiDayDomesticTrip = trip?.classification == .domesticTrip
            && (trip?.travelContext.overnightCount ?? 0) >= config.memoryPotentialMultiDayTripOvernightThreshold
        note("Multi-day Domestic Trip", "\(trip?.travelContext.overnightCount ?? 0) nights", isMultiDayDomesticTrip)

        let isAway = coordinate.map {
            LocationContextResolver.resolve(
                latitude: $0.latitude, longitude: $0.longitude,
                home: home, familiarPlaces: familiarPlaces, config: config
            ) == .away
        } ?? false
        note("Away From Home", isAway ? "away" : "not away", isAway)

        let isLongDuration = durationHours >= config.memoryPotentialLongDurationHours
        note("Long Duration", String(format: "%.1fh", durationHours), isLongDuration)

        let isHighFavoriteCount = favoriteCount >= config.memoryPotentialMinimumFavoriteCount
        note("Favorite Count", "\(favoriteCount)", isHighFavoriteCount)

        let isHighFavoriteRatio = favoriteRatio >= config.memoryPotentialMinimumFavoriteRatio
        note("Favorite Ratio", String(format: "%.0f%%", favoriteRatio * 100), isHighFavoriteRatio)

        let isDiverseSessions = event.sessionCount >= config.memoryPotentialMinimumSessionDiversity
        note("Session Diversity", "\(event.sessionCount) sessions", isDiverseSessions)

        let isMeaningfulPhotoCount = assets.count >= config.memoryPotentialMinimumAssetCountForSignal
        note("Photo Count", "\(assets.count) photos", isMeaningfulPhotoCount)

        let strongSignalMet = [
            isInternationalTrip, isMultiDayDomesticTrip, isAway, isLongDuration,
            isHighFavoriteCount, isHighFavoriteRatio, isDiverseSessions, isMeaningfulPhotoCount
        ].contains(true)

        let isAutoMemory = baseGateMet && strongSignalMet

        var scoredEvent = event
        scoredEvent.isAutoMemory = isAutoMemory
        scoredEvent.autoMemoryScore = event.eventQualityScore

        return Result(
            event: scoredEvent,
            trace: MemoryPotentialTrace(
                eventID: event.id, score: scoredEvent.autoMemoryScore, isAutoMemory: isAutoMemory, reasons: reasons
            )
        )
    }

    private static func averageCoordinate(of assets: [IndexedAsset]) -> (latitude: Double, longitude: Double)? {
        let located = assets.filter { $0.latitude != nil && $0.longitude != nil }
        guard !located.isEmpty else { return nil }
        let latitude = located.map { $0.latitude! }.reduce(0, +) / Double(located.count)
        let longitude = located.map { $0.longitude! }.reduce(0, +) / Double(located.count)
        return (latitude, longitude)
    }
}
