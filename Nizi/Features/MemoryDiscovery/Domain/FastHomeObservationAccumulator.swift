//
//  FastHomeObservationAccumulator.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// Grows across scan batches, capping GPS observations per calendar month (SPEC § 16) so one
/// 2,000-photo vacation month can't drown out years of lightly-photographed home life. A plain
/// mutable struct, not an actor — driven synchronously from `FirstExperienceCoordinator`, which
/// is already `@MainActor`, so no extra isolation is needed.
struct FastHomeObservationAccumulator {
    private var observationsByMonthKey: [String: [FastHomeObservation]] = [:]
    private let maxPerMonth: Int
    private let calendar = Calendar.current

    init(maxPerMonth: Int = FastHomeCandidateConfig.default.maxObservationsPerMonth) {
        self.maxPerMonth = maxPerMonth
    }

    mutating func add(records: [PhotoAssetRecord]) {
        for record in records {
            guard let latitude = record.latitude, let longitude = record.longitude, let date = record.creationDate else { continue }
            let components = calendar.dateComponents([.year, .month], from: date)
            let key = "\(components.year ?? 0)-\(components.month ?? 0)"
            guard (observationsByMonthKey[key]?.count ?? 0) < maxPerMonth else { continue }
            observationsByMonthKey[key, default: []].append(FastHomeObservation(latitude: latitude, longitude: longitude, date: date))
        }
    }

    var allObservations: [FastHomeObservation] {
        observationsByMonthKey.values.flatMap { $0 }
    }
}
