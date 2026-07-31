//
//  EventDiscoveryEngine.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Pure, deterministic metadata-rules clustering — no PhotoKit, no persistence, no randomness.
/// Pipeline: temporal segmentation → session building → session merging → scoring/filtering.
/// See docs/modules/memory-discovery/SPEC.md § 10–12 and ADR-MD-007 (rules before AI).
enum EventDiscoveryEngine {
    struct Result {
        let sessions: [PhotoSession]
        let events: [PhotoEvent]
        /// Location Intelligence + Trip Discovery output (SPRINT-SMART-EVENT-TRAVEL-DISCOVERY).
        /// `trips` are still unclassified (`.unknown`) here — country resolution needs
        /// reverse-geocoding, done afterward at the Application layer.
        let locationClusters: [LocationCluster]
        let home: HomeAnchor?
        let familiarPlaces: [FamiliarPlace]
        let trips: [PhotoTrip]
    }

    static func discover(
        from assets: [IndexedAsset],
        config: EventDiscoveryConfig = .default,
        boundaryEvaluator: EventBoundaryEvaluating? = nil,
        tripDetector: TripDetecting = DefaultTripDiscoveryEngine(),
        now: Date = Date()
    ) -> Result {
        let evaluator = boundaryEvaluator ?? DefaultEventBoundaryEvaluator(config: config)

        let sorted = assets.sorted { $0.creationDate < $1.creationDate }
        guard !sorted.isEmpty else {
            return Result(sessions: [], events: [], locationClusters: [], home: nil, familiarPlaces: [], trips: [])
        }

        let assetsByID = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0) })

        let locationIntelligence = LocationIntelligenceEngine.analyze(from: sorted, config: config)

        let temporalGroups = segmentByTime(sorted, config: config)
        let sessions = temporalGroups.map(buildSession)
        let sessionGroups = groupSessionsForMerging(
            sessions, config: config, evaluator: evaluator,
            home: locationIntelligence.home, familiarPlaces: locationIntelligence.familiarPlaces
        )

        let events = sessionGroups.compactMap { group -> PhotoEvent? in
            let groupAssets = group.flatMap(\.assetIDs).compactMap { assetsByID[$0] }
            return buildEvent(sessions: group, assets: groupAssets, config: config, now: now)
        }

        let trips = tripDetector.detectTrips(
            events: events, sessions: sessions, home: locationIntelligence.home, config: config
        )

        return Result(
            sessions: sessions, events: events,
            locationClusters: locationIntelligence.clusters,
            home: locationIntelligence.home,
            familiarPlaces: locationIntelligence.familiarPlaces,
            trips: trips
        )
    }

    // MARK: - Temporal segmentation

    private static func segmentByTime(
        _ sortedAssets: [IndexedAsset],
        config: EventDiscoveryConfig
    ) -> [[IndexedAsset]] {
        var groups: [[IndexedAsset]] = []
        var current: [IndexedAsset] = []

        for asset in sortedAssets {
            guard let previous = current.last else {
                current = [asset]
                continue
            }

            let gapSeconds = asset.creationDate.timeIntervalSince(previous.creationDate)
            let gapMinutes = gapSeconds / 60
            let gapHours = gapSeconds / 3600

            let sameSession: Bool
            if gapMinutes <= config.tightGapMinutes {
                sameSession = true
            } else if gapHours <= config.moderateGapHours {
                sameSession = true
            } else if gapHours <= config.looseGapHours {
                sameSession = hasLocationSupport(previous, asset, config: config)
            } else {
                sameSession = false
            }

            if sameSession {
                current.append(asset)
            } else {
                groups.append(current)
                current = [asset]
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    private static func hasLocationSupport(
        _ a: IndexedAsset,
        _ b: IndexedAsset,
        config: EventDiscoveryConfig
    ) -> Bool {
        guard let aLat = a.latitude, let aLon = a.longitude,
              let bLat = b.latitude, let bLon = b.longitude
        else {
            return false
        }
        let distanceKm = haversineDistanceKm(lat1: aLat, lon1: aLon, lat2: bLat, lon2: bLon)
        return distanceKm <= config.moderateGapLocationSupportKm
    }

    // MARK: - Session building

    private static func buildSession(from assets: [IndexedAsset]) -> PhotoSession {
        let startDate = assets.first!.creationDate
        let endDate = assets.last!.creationDate
        let located = assets.filter { $0.latitude != nil && $0.longitude != nil }

        let centerLatitude = located.isEmpty ? nil : located.map { $0.latitude! }.reduce(0, +) / Double(located.count)
        let centerLongitude = located.isEmpty ? nil : located.map { $0.longitude! }.reduce(0, +) / Double(located.count)
        let cell: String? = if let centerLatitude, let centerLongitude {
            geoCell(latitude: centerLatitude, longitude: centerLongitude)
        } else {
            nil
        }

        let durationHours = max(endDate.timeIntervalSince(startDate) / 3600, 1.0 / 60)
        let densityScore = Double(assets.count) / durationHours

        return PhotoSession(
            id: UUID(),
            startDate: startDate,
            endDate: endDate,
            centerLatitude: centerLatitude,
            centerLongitude: centerLongitude,
            geoCell: cell,
            assetIDs: assets.map(\.id),
            densityScore: densityScore
        )
    }

    /// Coarse ~11km grid cell (0.1° rounding) — deliberately not a precise location, and never
    /// reverse-geocoded. See docs/modules/memory-discovery/ARCHITECTURE.md § 8.2.
    static func geoCell(latitude: Double, longitude: Double, precision: Double = 0.1) -> String {
        let roundedLat = (latitude / precision).rounded() * precision
        let roundedLon = (longitude / precision).rounded() * precision
        return String(format: "%.1f,%.1f", roundedLat, roundedLon)
    }

    // MARK: - Session merging into event groups

    /// Boundary decision now comes from `EventBoundaryEvaluating` (SPRINT-SMART-EVENT-TRAVEL-
    /// DISCOVERY § 14) instead of a flat gap+distance rule — same forward-scan loop shape as
    /// before, just a different condition source. `currentEventDurationHours`/`SessionCount` in
    /// the context track the group being built so far, feeding the evaluator's duration-scaled
    /// merge threshold (§ 22).
    private static func groupSessionsForMerging(
        _ sessions: [PhotoSession],
        config: EventDiscoveryConfig,
        evaluator: EventBoundaryEvaluating,
        home: HomeAnchor?,
        familiarPlaces: [FamiliarPlace]
    ) -> [[PhotoSession]] {
        guard let first = sessions.first else { return [] }
        var groups: [[PhotoSession]] = []
        var current: [PhotoSession] = [first]

        for session in sessions.dropFirst() {
            let previous = current[current.count - 1]
            let groupStart = current[0].startDate
            let context = EventBoundaryContext(
                home: home,
                familiarPlaces: familiarPlaces,
                currentEventDurationHours: previous.endDate.timeIntervalSince(groupStart) / 3600,
                currentEventSessionCount: current.count
            )
            let decision = evaluator.evaluate(previous: previous, next: session, context: context)

            if decision.action == .merge {
                current.append(session)
            } else {
                groups.append(current)
                current = [session]
            }
        }
        groups.append(current)
        return groups
    }

    // MARK: - Event building

    private static func buildEvent(
        sessions: [PhotoSession],
        assets: [IndexedAsset],
        config: EventDiscoveryConfig,
        now: Date
    ) -> PhotoEvent? {
        guard !assets.isEmpty else { return nil }

        // Acceptance: never surface a screenshot-only cluster.
        let screenshotCount = assets.filter(\.isScreenshot).count
        guard screenshotCount < assets.count else { return nil }

        let favoriteCount = assets.filter(\.isFavorite).count
        let isHighDensity = sessions.contains { $0.densityScore >= config.highDensityAssetsPerHour }
        let assetCount = assets.count

        guard assetCount >= config.minimumEventAssetCount
            || (assetCount >= config.reducedMinimumEventAssetCount && (favoriteCount > 0 || isHighDensity))
        else {
            return nil
        }

        let startDate = sessions.map(\.startDate).min()!
        let endDate = sessions.map(\.endDate).max()!
        let spatial = spatialCohesion(assets: assets, config: config)

        let score = computeScore(
            assets: assets,
            sessions: sessions,
            startDate: startDate,
            endDate: endDate,
            favoriteCount: favoriteCount,
            spatialCohesion: spatial,
            config: config
        )

        return PhotoEvent(
            id: UUID(),
            titleSuggestion: makeTitle(startDate: startDate, endDate: endDate),
            startDate: startDate,
            endDate: endDate,
            primaryLocationLabel: nil,
            eventType: classifyEventType(startDate: startDate, endDate: endDate),
            score: score,
            status: .new,
            isLoved: false,
            sessionIDs: sessions.map(\.id),
            assetIDs: assets.map(\.id),
            coverAssetID: pickCoverAssetID(assets: assets),
            discoveryReasons: makeReasons(
                assetCount: assetCount,
                startDate: startDate,
                endDate: endDate,
                sessionCount: sessions.count,
                favoriteCount: favoriteCount,
                spatialCohesion: spatial,
                config: config
            ),
            algorithmVersion: config.algorithmVersion,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func pickCoverAssetID(assets: [IndexedAsset]) -> String? {
        let favoritesNonScreenshot = assets.filter { $0.isFavorite && !$0.isScreenshot }
        let nonScreenshot = assets.filter { !$0.isScreenshot }
        let pool = !favoritesNonScreenshot.isEmpty ? favoritesNonScreenshot : nonScreenshot
        guard !pool.isEmpty else { return assets.first?.id }
        return pool[pool.count / 2].id
    }

    // MARK: - Scoring (SPEC § 12)

    private static func computeScore(
        assets: [IndexedAsset],
        sessions: [PhotoSession],
        startDate: Date,
        endDate: Date,
        favoriteCount: Int,
        spatialCohesion: Double,
        config: EventDiscoveryConfig
    ) -> Double {
        let temporal = temporalCohesion(assets: assets)
        let density = densityScore(sessions: sessions, config: config)
        let favoriteRatio = Double(favoriteCount) / Double(assets.count)
        let duration = durationValue(startDate: startDate, endDate: endDate)
        let diversity = mediaDiversity(assets: assets)
        let noise = noisePenalty(assets: assets, config: config)

        let rawScore = 0.30 * temporal
            + 0.25 * spatialCohesion
            + 0.20 * density
            + 0.10 * favoriteRatio
            + 0.10 * duration
            + 0.05 * diversity
            - noise

        return min(max(rawScore, 0), 1)
    }

    private static func temporalCohesion(assets: [IndexedAsset]) -> Double {
        guard assets.count > 1 else { return 1 }
        let dates = assets.map(\.creationDate).sorted()
        let gapsMinutes = zip(dates, dates.dropFirst()).map { $1.timeIntervalSince($0) / 60 }
        let averageGapMinutes = gapsMinutes.reduce(0, +) / Double(gapsMinutes.count)
        // A 3-hour average gap (the "needs support" threshold) or worse counts as no cohesion.
        return 1 - min(max(averageGapMinutes / 180, 0), 1)
    }

    private static func spatialCohesion(assets: [IndexedAsset], config: EventDiscoveryConfig) -> Double {
        let located = assets.filter { $0.latitude != nil && $0.longitude != nil }
        // No location data to judge by — neutral, neither rewarded nor penalized.
        guard located.count > 1 else { return 0.5 }

        let centerLat = located.map { $0.latitude! }.reduce(0, +) / Double(located.count)
        let centerLon = located.map { $0.longitude! }.reduce(0, +) / Double(located.count)
        let distances = located.map {
            haversineDistanceKm(lat1: centerLat, lon1: centerLon, lat2: $0.latitude!, lon2: $0.longitude!)
        }
        let averageDistanceKm = distances.reduce(0, +) / Double(distances.count)
        return 1 - min(max(averageDistanceKm / config.moderateGapLocationSupportKm, 0), 1)
    }

    private static func densityScore(sessions: [PhotoSession], config: EventDiscoveryConfig) -> Double {
        guard !sessions.isEmpty else { return 0 }
        let averageDensity = sessions.map(\.densityScore).reduce(0, +) / Double(sessions.count)
        let referenceDensity = config.highDensityAssetsPerHour * 2.5
        return min(max(averageDensity / referenceDensity, 0), 1)
    }

    private static func durationValue(startDate: Date, endDate: Date) -> Double {
        let days = endDate.timeIntervalSince(startDate) / 86400
        switch days {
        case ..<1:
            return 0.6
        case 1...5:
            return 1.0
        default:
            return min(max(1 - (days - 5) / 10, 0), 1)
        }
    }

    private static func mediaDiversity(assets: [IndexedAsset]) -> Double {
        let distinctTypes = Set(assets.map(\.mediaType))
        return min(Double(distinctTypes.count) / 2, 1)
    }

    private static func noisePenalty(assets: [IndexedAsset], config: EventDiscoveryConfig) -> Double {
        let screenshotRatio = Double(assets.filter(\.isScreenshot).count) / Double(assets.count)

        let burstCounts = Dictionary(grouping: assets.compactMap(\.burstIdentifier), by: { $0 }).mapValues(\.count)
        let largestBurstRatio = Double(burstCounts.values.max() ?? 0) / Double(assets.count)
        let burstPenalty = largestBurstRatio > config.largeBurstFractionThreshold ? 0.2 : 0.0

        return min(screenshotRatio * 0.5 + burstPenalty, 1)
    }

    // MARK: - Event type / title / reasons

    private static func classifyEventType(startDate: Date, endDate: Date) -> EventType {
        let calendar = Calendar(identifier: .gregorian)
        let dayCount = inclusiveDayCount(from: startDate, to: endDate, calendar: calendar)

        if dayCount <= 1 {
            return .dayEvent
        }
        if dayCount <= 3, isWeekendSpan(startDate: startDate, endDate: endDate, calendar: calendar) {
            return .weekend
        }
        return .trip
    }

    private static func inclusiveDayCount(from startDate: Date, to endDate: Date, calendar: Calendar) -> Int {
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        let days = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return days + 1
    }

    private static func isWeekendSpan(startDate: Date, endDate: Date, calendar: Calendar) -> Bool {
        // Gregorian weekday: 1 = Sunday, 7 = Saturday.
        let startWeekday = calendar.component(.weekday, from: startDate)
        let endWeekday = calendar.component(.weekday, from: endDate)
        return [1, 7].contains(startWeekday) || [1, 7].contains(endWeekday)
    }

    private static func makeTitle(startDate: Date, endDate: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let dayMonthFormatter = DateFormatter()
        dayMonthFormatter.dateFormat = "dd/MM"
        let fullFormatter = DateFormatter()
        fullFormatter.dateFormat = "dd/MM/yyyy"

        if calendar.isDate(startDate, inSameDayAs: endDate) {
            return fullFormatter.string(from: startDate)
        }
        return "\(dayMonthFormatter.string(from: startDate)) – \(fullFormatter.string(from: endDate))"
    }

    private static func makeReasons(
        assetCount: Int,
        startDate: Date,
        endDate: Date,
        sessionCount: Int,
        favoriteCount: Int,
        spatialCohesion: Double,
        config: EventDiscoveryConfig
    ) -> [DiscoveryReason] {
        let calendar = Calendar(identifier: .gregorian)
        let dayCount = inclusiveDayCount(from: startDate, to: endDate, calendar: calendar)
        let durationText = dayCount <= 1 ? "trong ngày" : "trong \(dayCount) ngày"

        var reasons: [DiscoveryReason] = [
            DiscoveryReason(kind: .assetCountOverDuration, text: "\(assetCount) ảnh \(durationText)")
        ]

        if sessionCount > 1 {
            reasons.append(DiscoveryReason(kind: .multipleSessions, text: "Có \(sessionCount) phiên chụp liên tiếp"))
        }
        if favoriteCount > 0 {
            reasons.append(DiscoveryReason(kind: .favoritesPresent, text: "\(favoriteCount) ảnh được đánh dấu Favorite"))
        }
        if spatialCohesion > config.sameAreaCohesionThreshold {
            reasons.append(DiscoveryReason(kind: .sameAreaMajority, text: "Phần lớn được chụp tại cùng khu vực"))
        }

        return reasons
    }

    // MARK: - Distance

    static func haversineDistanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadiusKm = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusKm * c
    }
}
