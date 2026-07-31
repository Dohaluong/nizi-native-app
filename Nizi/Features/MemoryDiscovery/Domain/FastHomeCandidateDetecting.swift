//
//  FastHomeCandidateDetecting.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// One sampled GPS+date observation — deliberately just enough for temporal-recurrence scoring,
/// no asset identity needed (SPRINT-INITIAL-SCAN-MEMORY-JOURNEY-HOME § 15).
struct FastHomeObservation: Equatable {
    let latitude: Double
    let longitude: Double
    let date: Date
}

/// Distinguishes an algorithmic guess from a choice the user actually made — see `HomeAnchor`.
enum HomeAnchorSource: String, Equatable {
    case inferred
    case userConfirmed
}

/// A plausible Home region, not a certainty — `score` never reaches production UI (§ 19), only
/// Diagnostics and the ranking logic use it.
struct HomeCandidate: Identifiable, Equatable {
    let id: UUID
    let centerLatitude: Double
    let centerLongitude: Double
    let radiusMeters: Double
    var displayName: String?
    let score: Double
    let distinctYears: Int
    let distinctMonths: Int
}

/// Deliberately separate from `EventDiscoveryConfig` — Fast Home Candidate is a different,
/// simpler algorithm by design (§ 2: "Không dùng Full Home Detector trong production"), not a
/// variant of the Full one, so it gets its own small config rather than bolting onto the big one.
struct FastHomeCandidateConfig {
    var clusterRadiusMeters: Double = 500
    var maxObservationsPerMonth: Int = 15
    var strongCandidateScore: Double = 0.75
    var plausibleCandidateScore: Double = 0.45
    var minimumPlausibleCandidates: Int = 2

    static let `default` = FastHomeCandidateConfig()
}

protocol FastHomeCandidateDetecting {
    func candidates(from observations: [FastHomeObservation], config: FastHomeCandidateConfig) -> [HomeCandidate]
}

/// Reuses `EventDiscoveryEngine.haversineDistanceKm` and the same greedy "first cluster within
/// radius, else new" rule as `LocationIntelligenceEngine.buildClusters`, but scores only
/// `distinctYearScore + distinctMonthScore + sampledDistinctDayScore + recurrenceScore` over the
/// small, per-month-capped observation set — no evening/visit-run signals (§ 15 explicitly
/// excludes those from Fast V1). Runs on whatever's been sampled so far, not the whole library.
struct DefaultFastHomeCandidateDetector: FastHomeCandidateDetecting {
    func candidates(from observations: [FastHomeObservation], config: FastHomeCandidateConfig) -> [HomeCandidate] {
        guard !observations.isEmpty else { return [] }
        let calendar = Calendar.current

        return buildClusters(from: observations, config: config)
            .map { cluster -> HomeCandidate in
                let years = Set(cluster.dates.map { calendar.component(.year, from: $0) })
                let months = Set(cluster.dates.map { date -> String in
                    let components = calendar.dateComponents([.year, .month], from: date)
                    return "\(components.year ?? 0)-\(components.month ?? 0)"
                })
                let distinctDays = Set(cluster.dates.map { calendar.startOfDay(for: $0) }).count

                let distinctYearScore = min(Double(years.count) / 3, 1)
                let distinctMonthScore = min(Double(months.count) / 12, 1)
                let sampledDistinctDayScore = min(Double(distinctDays) / 30, 1)
                // Recurrence proxy: how much of the per-month sampling budget this cluster used
                // across ~6 months' worth of quota — a place seen only once or twice stays low
                // even if a single burst of photos landed in it.
                let recurrenceScore = min(Double(cluster.dates.count) / Double(config.maxObservationsPerMonth * 6), 1)

                let score = 0.30 * distinctYearScore
                    + 0.30 * distinctMonthScore
                    + 0.25 * sampledDistinctDayScore
                    + 0.15 * recurrenceScore

                return HomeCandidate(
                    id: UUID(),
                    centerLatitude: cluster.centerLatitude,
                    centerLongitude: cluster.centerLongitude,
                    radiusMeters: cluster.radiusMeters,
                    displayName: nil,
                    score: score,
                    distinctYears: years.count,
                    distinctMonths: months.count
                )
            }
            .sorted { $0.score > $1.score }
    }

    // MARK: - Clustering

    private struct WorkingCluster {
        var latitudeSum: Double
        var longitudeSum: Double
        var count: Int
        var latitudes: [Double]
        var longitudes: [Double]
        var dates: [Date]
    }

    private struct FinalizedCluster {
        let centerLatitude: Double
        let centerLongitude: Double
        let radiusMeters: Double
        let dates: [Date]
    }

    private func buildClusters(from observations: [FastHomeObservation], config: FastHomeCandidateConfig) -> [FinalizedCluster] {
        let sorted = observations.sorted { $0.date < $1.date }
        var working: [WorkingCluster] = []

        for observation in sorted {
            let matchedIndex = working.firstIndex { cluster in
                let centroidLat = cluster.latitudeSum / Double(cluster.count)
                let centroidLon = cluster.longitudeSum / Double(cluster.count)
                let distanceMeters = EventDiscoveryEngine.haversineDistanceKm(
                    lat1: centroidLat, lon1: centroidLon, lat2: observation.latitude, lon2: observation.longitude
                ) * 1000
                return distanceMeters <= config.clusterRadiusMeters
            }

            if let matchedIndex {
                working[matchedIndex].latitudeSum += observation.latitude
                working[matchedIndex].longitudeSum += observation.longitude
                working[matchedIndex].count += 1
                working[matchedIndex].latitudes.append(observation.latitude)
                working[matchedIndex].longitudes.append(observation.longitude)
                working[matchedIndex].dates.append(observation.date)
            } else {
                working.append(WorkingCluster(
                    latitudeSum: observation.latitude, longitudeSum: observation.longitude, count: 1,
                    latitudes: [observation.latitude], longitudes: [observation.longitude], dates: [observation.date]
                ))
            }
        }

        return working.map { cluster in
            let centerLat = cluster.latitudeSum / Double(cluster.count)
            let centerLon = cluster.longitudeSum / Double(cluster.count)
            let radiusMeters = zip(cluster.latitudes, cluster.longitudes).map {
                EventDiscoveryEngine.haversineDistanceKm(lat1: centerLat, lon1: centerLon, lat2: $0, lon2: $1) * 1000
            }.max() ?? 0
            return FinalizedCluster(centerLatitude: centerLat, centerLongitude: centerLon, radiusMeters: radiusMeters, dates: cluster.dates)
        }
    }
}

/// SPEC § 17 — "đủ dùng" doesn't need Full-Detector-grade confidence: one very strong candidate,
/// or a couple of merely plausible ones, is enough to offer the card.
enum FastHomeCandidateReadiness {
    static func isReady(candidates: [HomeCandidate], config: FastHomeCandidateConfig) -> Bool {
        guard let top = candidates.first else { return false }
        if top.score >= config.strongCandidateScore { return true }
        return candidates.filter { $0.score >= config.plausibleCandidateScore }.count >= config.minimumPlausibleCandidates
    }
}
