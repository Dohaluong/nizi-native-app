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
        config: EventDiscoveryConfig
    ) -> [PhotoTrip]
}

/// Groups maximal runs of consecutive `.away`-context `PhotoEvent`s into `PhotoTrip`s — the
/// `HOME → AWAY → AWAY → AWAY → HOME` pattern from SPEC § 25. A `.local` outing never enters
/// grouping at all (SPEC § 28: "→ `.local`, Không phải Trip") — only genuinely away events do, so
/// there's no need for a separate `travelClassification` field on `PhotoEvent` itself.
///
/// Pure and synchronous — country/place resolution (needs reverse-geocoding) happens afterward,
/// at the Application layer, via `TravelClassificationService`. `classification` here is always
/// `.unknown` until that pass runs.
struct DefaultTripDiscoveryEngine: TripDetecting {
    func detectTrips(
        events: [PhotoEvent],
        sessions: [PhotoSession],
        home: HomeAnchor?,
        config: EventDiscoveryConfig
    ) -> [PhotoTrip] {
        // Can't tell "away" from "home" without a Home anchor — no trips, engine keeps working.
        guard let home else { return [] }

        let sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let sortedEvents = events.sorted { $0.startDate < $1.startDate }

        let annotated: [AnnotatedEvent] = sortedEvents.map { event in
            let coordinate = representativeCoordinate(for: event, sessionsByID: sessionsByID)
            let context = LocationContextResolver.resolve(
                latitude: coordinate?.latitude, longitude: coordinate?.longitude,
                home: home, familiarPlaces: [], config: config
            )
            return AnnotatedEvent(event: event, coordinate: coordinate, context: context)
        }

        var trips: [PhotoTrip] = []
        var currentGroup: [AnnotatedEvent] = []
        var groupPrecededByHome = false

        for (index, annotatedEvent) in annotated.enumerated() {
            guard annotatedEvent.context == .away else {
                if !currentGroup.isEmpty {
                    trips.append(buildTrip(
                        from: currentGroup, home: home,
                        precededByHome: groupPrecededByHome, followedByHome: annotatedEvent.context == .home
                    ))
                    currentGroup = []
                }
                groupPrecededByHome = false
                continue
            }

            if currentGroup.isEmpty {
                groupPrecededByHome = index > 0 && annotated[index - 1].context == .home
            } else if let previousEvent = currentGroup.last?.event {
                let gapHours = annotatedEvent.event.startDate.timeIntervalSince(previousEvent.endDate) / 3600
                if gapHours > config.minimumTripTerminationGapHours {
                    trips.append(buildTrip(from: currentGroup, home: home, precededByHome: groupPrecededByHome, followedByHome: false))
                    currentGroup = []
                    groupPrecededByHome = false
                }
            }
            currentGroup.append(annotatedEvent)
        }

        if !currentGroup.isEmpty {
            trips.append(buildTrip(from: currentGroup, home: home, precededByHome: groupPrecededByHome, followedByHome: false))
        }

        return trips
    }

    private struct AnnotatedEvent {
        let event: PhotoEvent
        let coordinate: (latitude: Double, longitude: Double)?
        let context: LocationContext
    }

    private func representativeCoordinate(
        for event: PhotoEvent,
        sessionsByID: [UUID: PhotoSession]
    ) -> (latitude: Double, longitude: Double)? {
        let located = event.sessionIDs.compactMap { sessionsByID[$0] }
            .filter { $0.centerLatitude != nil && $0.centerLongitude != nil }
        guard !located.isEmpty else { return nil }
        let latitude = located.map { $0.centerLatitude! }.reduce(0, +) / Double(located.count)
        let longitude = located.map { $0.centerLongitude! }.reduce(0, +) / Double(located.count)
        return (latitude, longitude)
    }

    private func buildTrip(
        from group: [AnnotatedEvent],
        home: HomeAnchor,
        precededByHome: Bool,
        followedByHome: Bool
    ) -> PhotoTrip {
        let events = group.map(\.event)
        let startDate = events.map(\.startDate).min() ?? Date()
        let endDate = events.map(\.endDate).max() ?? startDate
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
                guard let coordinate = annotated.coordinate else { return nil }
                let distanceKm = EventDiscoveryEngine.haversineDistanceKm(
                    lat1: home.centerLatitude, lon1: home.centerLongitude,
                    lat2: coordinate.latitude, lon2: coordinate.longitude
                )
                return (coordinate, distanceKm)
            }
            .max { $0.distanceKm < $1.distanceKm }

        let travelContext = TravelContext(
            homeCountryCode: nil,
            maxDistanceFromHomeKm: farthest?.distanceKm,
            overnightCount: overnightCount,
            countryCodes: [],
            hasDepartureFromHome: precededByHome,
            hasReturnToHome: followedByHome
        )

        let confidence = min(
            0.5 + 0.1 * Double(events.count)
                + (precededByHome ? 0.1 : 0) + (followedByHome ? 0.2 : 0),
            1.0
        )

        return PhotoTrip(
            id: UUID(),
            startDate: startDate,
            endDate: endDate,
            eventIDs: events.map(\.id),
            primaryLatitude: farthest?.coordinate.latitude,
            primaryLongitude: farthest?.coordinate.longitude,
            primaryCountryCode: nil,
            primaryPlaceName: nil,
            classification: .unknown,
            confidence: confidence,
            travelContext: travelContext
        )
    }
}
