//
//  TripDiscoveryEngine.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// SPEC § 25, verbatim shape.
protocol TripDetecting {
    func detectTrips(
        events: [PhotoEvent],
        sessions: [PhotoSession],
        home: HomeAnchor?,
        familiarPlaces: [FamiliarPlace],
        config: EventDiscoveryConfig
    ) -> [PhotoTrip]
}

/// Candidate-based journey detection. Sessions are the primary evidence; Events only increase
/// confidence when they happen to exist. This lets discovery retain a multi-day journey even
/// when sparse photos fail Event acceptance or a session has no GPS.
struct DefaultTripDiscoveryEngine: TripDetecting {
    let eligibilityEvaluator: TripEligibilityEvaluating

    init(eligibilityEvaluator: TripEligibilityEvaluating = DefaultTripEligibilityEvaluator()) {
        self.eligibilityEvaluator = eligibilityEvaluator
    }

    func detectTrips(
        events: [PhotoEvent],
        sessions: [PhotoSession],
        home: HomeAnchor?,
        familiarPlaces: [FamiliarPlace],
        config: EventDiscoveryConfig
    ) -> [PhotoTrip] {
        let eventsBySessionID = Dictionary(uniqueKeysWithValues: events.flatMap { event in
            event.sessionIDs.map { ($0, event) }
        })
        let annotated = sessions.sorted { $0.startDate < $1.startDate }.map { session in
            let coordinate = coordinate(for: session)
            let context: LocationContext
            if let coordinate {
                context = LocationContextResolver.resolve(
                    latitude: coordinate.latitude, longitude: coordinate.longitude,
                    home: home, familiarPlaces: familiarPlaces, config: config
                )
            } else {
                context = .unknown
            }
            return AnnotatedSession(session: session, event: eventsBySessionID[session.id], coordinate: coordinate, context: context)
        }

        var trips: [PhotoTrip] = []
        var currentGroup: [AnnotatedSession] = []
        var groupPrecededByHome = false

        for (index, annotatedSession) in annotated.enumerated() {
            // Only an explicit Home visit ends a journey. Unknown is intentionally bridged: a
            // missing GPS row is absence of evidence, not evidence that the user returned home.
            if annotatedSession.context == .home || annotatedSession.context == .local {
                if !currentGroup.isEmpty {
                    appendTripIfEligible(
                        currentGroup, home: home, precededByHome: groupPrecededByHome,
                        followedByHome: annotatedSession.context == .home, config: config, into: &trips
                    )
                    currentGroup = []
                }
                groupPrecededByHome = false
                continue
            }

            if currentGroup.isEmpty {
                // With no Home anchor, every located session can start a low-confidence
                // candidate. A GPS-less session cannot create one by itself, but can bridge one.
                guard annotatedSession.coordinate != nil else { continue }
                groupPrecededByHome = index > 0 && annotated[index - 1].context == .home
            } else if let previousSession = currentGroup.last?.session {
                let gapHours = annotatedSession.session.startDate.timeIntervalSince(previousSession.endDate) / 3600
                if gapHours > config.minimumTripTerminationGapHours {
                    appendTripIfEligible(
                        currentGroup, home: home, precededByHome: groupPrecededByHome,
                        followedByHome: false, config: config, into: &trips
                    )
                    currentGroup = annotatedSession.coordinate == nil ? [] : [annotatedSession]
                    groupPrecededByHome = false
                    continue
                }
            }
            currentGroup.append(annotatedSession)
        }

        if !currentGroup.isEmpty {
            appendTripIfEligible(
                currentGroup, home: home, precededByHome: groupPrecededByHome,
                followedByHome: false, config: config, into: &trips
            )
        }

        return trips
    }

    private func appendTripIfEligible(
        _ group: [AnnotatedSession], home: HomeAnchor?, precededByHome: Bool, followedByHome: Bool,
        config: EventDiscoveryConfig, into trips: inout [PhotoTrip]
    ) {
        var trip = buildTrip(from: group, home: home, precededByHome: precededByHome, followedByHome: followedByHome)
        let hasCoordinate = group.contains { $0.coordinate != nil }
        let hasUnknownBridge = group.contains { $0.coordinate == nil }
        let eventCount = Set(group.compactMap(\.event).map(\.id)).count
        var confidence = hasCoordinate ? 0.40 : 0
        var reasons = hasCoordinate ? ["sessionLocation"] : []
        if home != nil { confidence += 0.12; reasons.append("homeContext") }
        if trip.travelContext.overnightCount >= 1 { confidence += 0.20; reasons.append("overnight") }
        if group.count >= 2 { confidence += 0.12; reasons.append("multipleSessions") }
        if eventCount > 0 { confidence += 0.08; reasons.append("eventSupport") }
        if hasUnknownBridge { confidence += 0.05; reasons.append("bridgedUnknownGPS") }
        guard confidence >= config.tripCandidateMinimumConfidence else { return }
        trip.travelContext.eligibilityReasons = reasons
        trip.confidence = min(confidence, 1)
        trips.append(trip)
    }

    private struct AnnotatedSession {
        let session: PhotoSession
        let event: PhotoEvent?
        let coordinate: (latitude: Double, longitude: Double)?
        let context: LocationContext
    }

    private func coordinate(for session: PhotoSession) -> (latitude: Double, longitude: Double)? {
        guard let latitude = session.centerLatitude, let longitude = session.centerLongitude else { return nil }
        return (latitude, longitude)
    }

    private func buildTrip(
        from group: [AnnotatedSession],
        home: HomeAnchor?,
        precededByHome: Bool,
        followedByHome: Bool
    ) -> PhotoTrip {
        let sessions = group.map(\.session)
        let events = Array(Dictionary(uniqueKeysWithValues: group.compactMap { item in
            item.event.map { ($0.id, $0) }
        }).values)
        let startDate = sessions.map(\.startDate).min() ?? Date()
        let endDate = sessions.map(\.endDate).max() ?? startDate
        let calendar = Calendar.current
        let overnightCount = max(
            calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: startDate), to: calendar.startOfDay(for: endDate)
            ).day ?? 0,
            0
        )

        // The farthest point doubles as both the distance signal and the representative
        // coordinate for country resolution — a trip that goes further from home is more
        // representative of "where this trip actually went" than an average of every stop.
        let farthest = group
            .compactMap { annotated -> (coordinate: (latitude: Double, longitude: Double), distanceKm: Double)? in
                guard let home, let coordinate = annotated.coordinate else { return nil }
                let distanceKm = EventDiscoveryEngine.haversineDistanceKm(
                    lat1: home.centerLatitude, lon1: home.centerLongitude,
                    lat2: coordinate.latitude, lon2: coordinate.longitude
                )
                return (coordinate, distanceKm)
            }
            .max { $0.distanceKm < $1.distanceKm }

        let representative = farthest?.coordinate ?? group.compactMap(\.coordinate).last
        let travelContext = TravelContext(
            homeCountryCode: nil,
            maxDistanceFromHomeKm: farthest?.distanceKm,
            overnightCount: overnightCount,
            countryCodes: [],
            hasDepartureFromHome: precededByHome,
            hasReturnToHome: followedByHome
        )

        let confidence = min(
            0.4 + 0.06 * Double(sessions.count)
                + (precededByHome ? 0.1 : 0) + (followedByHome ? 0.2 : 0),
            1.0
        )

        return PhotoTrip(
            id: UUID(),
            startDate: startDate,
            endDate: endDate,
            eventIDs: events.map(\.id),
            primaryLatitude: representative?.latitude,
            primaryLongitude: representative?.longitude,
            primaryCountryCode: nil,
            primaryPlaceName: nil,
            classification: .unknown,
            confidence: confidence,
            travelContext: travelContext
        )
    }
}
