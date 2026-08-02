//
//  LocationIntelligenceEngine.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// Pure, deterministic — library-wide location clustering (§7), Home detection (§8-11), and
/// Familiar Place detection (§12), in one pass since all three share the same clustering
/// substrate. Mirrors `EventDiscoveryEngine`'s own "one namespace, one `Result`" shape.
///
/// Clustering is plain greedy O(n×k) — sort by date, assign each asset to the first existing
/// cluster whose running centroid is within `config.locationClusterRadiusMeters`, else start a
/// new one — the same approach `PhotoLocationClustering.DefaultPhotoLocationClusterer` already
/// uses at Album-planning scale, with no spatial index. The number of distinct real-world places
/// in a library is normally in the dozens–low-hundreds even at 100k+ photos, so this stays fast;
/// geoCell pre-bucketing is a known optimization if that ever proves wrong, not built preemptively.
enum LocationIntelligenceEngine {
    struct Result {
        let clusters: [LocationCluster]
        let home: HomeAnchor?
        let familiarPlaces: [FamiliarPlace]
    }

    /// `skipHomeDetection` (SPRINT-NEXT § 3-4): when the caller already has a user-confirmed
    /// `HomeAnchor`, there's no point computing a fresh guess only to discard it — set by
    /// `EventDiscoveryEngine.discover` whenever `preferredHome?.source == .userConfirmed`.
    static func analyze(
        from assets: [IndexedAsset], config: EventDiscoveryConfig = .default, skipHomeDetection: Bool = false
    ) -> Result {
        let located = assets.filter { $0.latitude != nil && $0.longitude != nil }
        guard !located.isEmpty else { return Result(clusters: [], home: nil, familiarPlaces: []) }

        let clusters = buildClusters(from: located, config: config)
        let home = skipHomeDetection ? nil : detectHome(clusters: clusters, config: config)
        let familiarPlaces = detectFamiliarPlaces(clusters: clusters, excluding: home?.clusterID, config: config)

        return Result(clusters: clusters, home: home, familiarPlaces: familiarPlaces)
    }

    // MARK: - Clustering (§7)

    private struct WorkingCluster {
        var latitudeSum: Double
        var longitudeSum: Double
        var count: Int
        var assetIDs: [String]
        var latitudes: [Double]
        var longitudes: [Double]
        var dates: [Date]
    }

    private static func buildClusters(from located: [IndexedAsset], config: EventDiscoveryConfig) -> [LocationCluster] {
        let sorted = located.sorted { $0.creationDate < $1.creationDate }
        var working: [WorkingCluster] = []

        for asset in sorted {
            guard let lat = asset.latitude, let lon = asset.longitude else { continue }

            let matchedIndex = working.firstIndex { cluster in
                let centroidLat = cluster.latitudeSum / Double(cluster.count)
                let centroidLon = cluster.longitudeSum / Double(cluster.count)
                let distanceMeters = EventDiscoveryEngine.haversineDistanceKm(
                    lat1: centroidLat, lon1: centroidLon, lat2: lat, lon2: lon
                ) * 1000
                return distanceMeters <= config.locationClusterRadiusMeters
            }

            if let matchedIndex {
                working[matchedIndex].latitudeSum += lat
                working[matchedIndex].longitudeSum += lon
                working[matchedIndex].count += 1
                working[matchedIndex].assetIDs.append(asset.id)
                working[matchedIndex].latitudes.append(lat)
                working[matchedIndex].longitudes.append(lon)
                working[matchedIndex].dates.append(asset.creationDate)
            } else {
                working.append(WorkingCluster(
                    latitudeSum: lat, longitudeSum: lon, count: 1,
                    assetIDs: [asset.id], latitudes: [lat], longitudes: [lon], dates: [asset.creationDate]
                ))
            }
        }

        return working.map(finalizeCluster)
    }

    private static func finalizeCluster(_ working: WorkingCluster) -> LocationCluster {
        let centerLat = working.latitudeSum / Double(working.count)
        let centerLon = working.longitudeSum / Double(working.count)
        let radiusMeters = zip(working.latitudes, working.longitudes).map {
            EventDiscoveryEngine.haversineDistanceKm(lat1: centerLat, lon1: centerLon, lat2: $0, lon2: $1) * 1000
        }.max() ?? 0

        let calendar = Calendar.current
        let dayKeys = Set(working.dates.map { calendar.startOfDay(for: $0) }).sorted()
        let monthKeys = Set(working.dates.map { date in
            let components = calendar.dateComponents([.year, .month], from: date)
            return "\(components.year ?? 0)-\(components.month ?? 0)"
        })

        // Separate visits: a gap of more than one calendar day between distinct days starts a
        // new run, so "5 consecutive daily photos" counts as one visit, not five.
        var visitRunCount = 0
        var previousDay: Date?
        for day in dayKeys {
            if let previousDay, (calendar.dateComponents([.day], from: previousDay, to: day).day ?? 2) <= 1 {
                // same run — no increment
            } else {
                visitRunCount += 1
            }
            previousDay = day
        }

        let eveningOrNightCount = working.dates.filter { date in
            let hour = calendar.component(.hour, from: date)
            return hour >= 18 || hour < 6
        }.count

        return LocationCluster(
            id: UUID(),
            centerLatitude: centerLat,
            centerLongitude: centerLon,
            radiusMeters: radiusMeters,
            assetIDs: working.assetIDs,
            distinctDayCount: dayKeys.count,
            distinctMonthCount: monthKeys.count,
            visitRunCount: visitRunCount,
            firstSeenAt: working.dates.min() ?? Date(),
            lastSeenAt: working.dates.max() ?? Date(),
            eveningOrNightAssetRatio: Double(eveningOrNightCount) / Double(working.dates.count)
        )
    }

    // MARK: - Home detection (§8-11)

    /// Deliberately never uses `assetCount` — a short, photo-heavy vacation must not outscore a
    /// long-term, lightly-photographed home (SPEC § 9's explicit warning, and Fixture H). Not
    /// `private` — `HomeDetectionDiagnosticsView` recomputes this per-candidate to rank every
    /// cluster, not just the winner.
    static func homeScore(for cluster: LocationCluster) -> Double {
        let distinctDayScore = min(Double(cluster.distinctDayCount) / 60, 1)
        let distinctMonthScore = min(Double(cluster.distinctMonthCount) / 6, 1)
        let spanDays = cluster.lastSeenAt.timeIntervalSince(cluster.firstSeenAt) / 86400
        let longTermPresenceScore = min(spanDays / 180, 1)
        let eveningPresenceScore = cluster.eveningOrNightAssetRatio
        // "Recurrence"/"return frequency" (SPEC § 9) collapse into one signal here — separate
        // distinctDayCount and visitRunCount already capture the same underlying idea (raw days
        // present vs. distinct times they came back) without a redundant sixth term.
        let returnScore = min(Double(cluster.visitRunCount) / 10, 1)

        return 0.25 * distinctDayScore
            + 0.20 * distinctMonthScore
            + 0.20 * longTermPresenceScore
            + 0.15 * eveningPresenceScore
            + 0.20 * returnScore
    }

    static func homeConfidence(for score: Double, config: EventDiscoveryConfig) -> HomeConfidence? {
        if score >= config.homeConfidenceThreshold { return .high }
        if score >= config.homeConfidenceMediumThreshold { return .medium }
        if score >= config.homeConfidenceLowThreshold { return .low }
        return nil
    }

    private static func detectHome(clusters: [LocationCluster], config: EventDiscoveryConfig) -> HomeAnchor? {
        let eligible = clusters.filter { $0.distinctDayCount >= config.minimumHomeDistinctDays }
        let scored = eligible.map { (cluster: $0, score: homeScore(for: $0)) }
        guard let best = scored.max(by: { $0.score < $1.score }) else { return nil }
        // Too little history overall — SPEC § 10: "Home = unknown", engine keeps working without it.
        guard let confidence = homeConfidence(for: best.score, config: config) else { return nil }

        return HomeAnchor(
            clusterID: best.cluster.id,
            centerLatitude: best.cluster.centerLatitude,
            centerLongitude: best.cluster.centerLongitude,
            homeScore: best.score,
            confidence: confidence
        )
    }

    // MARK: - Familiar place detection (§12)

    private static func detectFamiliarPlaces(
        clusters: [LocationCluster],
        excluding homeClusterID: UUID?,
        config: EventDiscoveryConfig
    ) -> [FamiliarPlace] {
        clusters
            .filter { $0.id != homeClusterID && $0.distinctDayCount >= config.minimumFamiliarDistinctDays }
            .map { cluster in
                FamiliarPlace(
                    id: cluster.id, clusterID: cluster.id,
                    centerLatitude: cluster.centerLatitude, centerLongitude: cluster.centerLongitude,
                    confidence: homeScore(for: cluster)
                )
            }
            .sorted { $0.confidence > $1.confidence }
    }
}
