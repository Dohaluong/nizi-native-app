import Foundation

/// Chooses one dominant GPS area for an Event. It first reuses the persistent library location
/// clusters, then falls back to the densest coarse coordinate bucket — never a naive average of
/// an entire multi-place event.
struct DefaultEventRepresentativeLocationProvider {
    let assetRepository: LocalAssetRepository
    let locationRepository: LocationIntelligenceRepository

    func representativeCoordinate(for event: PhotoEvent) async -> PhotoCoordinate? {
        guard let assets = try? await assetRepository.fetchAssets(ids: event.assetIDs) else { return nil }
        let located = assets.compactMap { asset -> PhotoCoordinate? in
            guard let latitude = asset.latitude, let longitude = asset.longitude else { return nil }
            return PhotoCoordinate(latitude: latitude, longitude: longitude)
        }
        guard !located.isEmpty else { return nil }

        let eventAssetIDs = Set(event.assetIDs)
        if let clusters = try? await locationRepository.fetchLocationClusters(),
           let dominant = clusters.max(by: {
               Set($0.assetIDs).intersection(eventAssetIDs).count < Set($1.assetIDs).intersection(eventAssetIDs).count
           }), Set(dominant.assetIDs).intersection(eventAssetIDs).isEmpty == false {
            return PhotoCoordinate(latitude: dominant.centerLatitude, longitude: dominant.centerLongitude)
        }

        let buckets = Dictionary(grouping: located) { coordinate in
            "\(Int((coordinate.latitude * 100).rounded())):\(Int((coordinate.longitude * 100).rounded()))"
        }
        guard let dominant = buckets.values.max(by: { $0.count < $1.count }), !dominant.isEmpty else { return nil }
        let latitude = dominant.map(\.latitude).reduce(0, +) / Double(dominant.count)
        let longitude = dominant.map(\.longitude).reduce(0, +) / Double(dominant.count)
        return PhotoCoordinate(latitude: latitude, longitude: longitude)
    }
}

struct EventPlaceDisplayNameFormatter {
    func displayName(for place: PhotoPlace, homeCountryCode: String?) -> String? {
        let parts: [String]
        if place.isoCountryCode?.uppercased() == "VN" {
            // Apple is inconsistent across Vietnam: the post-reform Phường/Xã can be supplied
            // as `subLocality`, `locality`, or `subAdministrativeArea`. The province/municipality
            // is `administrativeArea`, so retain both levels whenever available.
            let ward = cleaned(place.subLocality)
                ?? cleaned(place.locality)
                ?? cleaned(place.subAdministrativeArea)
            let city = cleaned(place.administrativeArea)
                ?? [cleaned(place.subAdministrativeArea), cleaned(place.locality)]
                    .compactMap { $0 }
                    .first(where: { $0 != ward })
            if let ward, let city, ward != city { return "\(ward) - \(city)" }
            return city ?? ward ?? cleaned(place.country)
        }

        if let countryCode = place.isoCountryCode, let homeCountryCode,
           countryCode.uppercased() == homeCountryCode.uppercased() {
            return unique([place.locality, place.administrativeArea, place.country]).first
        }
        parts = unique([place.locality, place.administrativeArea, place.country])
        return parts.prefix(2).joined(separator: " - ").nilIfEmpty
    }

    private func unique(_ values: [String?]) -> [String] {
        values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: []) { result, value in if !result.contains(value) { result.append(value) } }
    }

    private func cleaned(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

/// Shared actor cache deduplicates cards resolving the same rounded coordinate in a session.
actor EventPlaceEnrichmentService {
    static let shared = EventPlaceEnrichmentService()

    private let resolver: PhotoPlaceResolving = ApplePhotoPlaceResolver()
    private var cached: [PhotoPlaceCacheKey: PhotoPlace] = [:]
    private var inFlight: [PhotoPlaceCacheKey: Task<PhotoPlace?, Never>] = [:]
    private let formatter = EventPlaceDisplayNameFormatter()

    func resolve(coordinate: PhotoCoordinate, homeCountryCode: String?) async -> EventPlace? {
        let key = PhotoPlaceCacheKey(coordinate: coordinate)
        if let place = cached[key] {
            NiziLogger.discovery.notice("event_place_cache_hit")
            return makeEventPlace(place, coordinate: coordinate, homeCountryCode: homeCountryCode)
        }
        let task: Task<PhotoPlace?, Never>
        if let existing = inFlight[key] {
            task = existing
        } else {
            NiziLogger.discovery.notice("event_place_geocode_started")
            task = Task { [resolver] in try? await resolver.resolvePlace(for: coordinate) }
            inFlight[key] = task
        }
        let place = await task.value
        inFlight[key] = nil
        guard let place else { return nil }
        cached[key] = place
        return makeEventPlace(place, coordinate: coordinate, homeCountryCode: homeCountryCode)
    }

    private func makeEventPlace(_ place: PhotoPlace, coordinate: PhotoCoordinate, homeCountryCode: String?) -> EventPlace? {
        guard let displayName = formatter.displayName(for: place, homeCountryCode: homeCountryCode) else { return nil }
        NiziLogger.discovery.notice("event_place_resolved country=\(place.isoCountryCode ?? "nil", privacy: .public) subLocality=\(place.subLocality ?? "nil", privacy: .public) locality=\(place.locality ?? "nil", privacy: .public) subAdministrativeArea=\(place.subAdministrativeArea ?? "nil", privacy: .public) administrativeArea=\(place.administrativeArea ?? "nil", privacy: .public) display=\(displayName, privacy: .public)")
        return EventPlace(coordinate: coordinate, subLocality: place.subLocality, locality: place.locality,
                          subAdministrativeArea: place.subAdministrativeArea, administrativeArea: place.administrativeArea, country: place.country,
                          countryCode: place.isoCountryCode, displayName: displayName)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Downstream-only enrichment entry point used by visible Event cards and Event Detail. It never
/// invokes discovery or a scan; a persisted resolved/unavailable Event is returned untouched.
func enrichPlaceIfNeeded(for event: PhotoEvent, store: SwiftDataMemoryDiscoveryStore) async -> PhotoEvent {
    guard eventNeedsPlaceResolution(event) else { return event }
    NiziLogger.discovery.notice("event_place_requested eventID=\(event.id, privacy: .public)")
    let provider = DefaultEventRepresentativeLocationProvider(assetRepository: store, locationRepository: store)
    guard let coordinate = await provider.representativeCoordinate(for: event) else {
        try? await store.setEventPlace(eventID: event.id, place: nil, state: .unavailable)
        return event
    }
    let homeCountryCode = Locale.current.regionCode ?? "VN"
    let place = await EventPlaceEnrichmentService.shared.resolve(
        coordinate: coordinate, homeCountryCode: homeCountryCode
    )
    let state: EventPlaceResolutionState = place == nil ? .unavailable : .resolved
    try? await store.setEventPlace(eventID: event.id, place: place, state: state)
    var updated = event
    updated.eventPlace = place
    updated.primaryLocationLabel = place?.displayName
    updated.placeResolutionState = state
    return updated
}

func needsVietnamesePlaceUpgrade(_ event: PhotoEvent) -> Bool {
    guard let label = event.primaryLocationLabel, !label.isEmpty, !label.contains(" - ") else { return false }
    // Older rows predate `EventPlace` and therefore have no country code. The app's supported
    // product locale is VN, so re-resolving their single-part label is safe and repairs them.
    return event.eventPlace?.countryCode?.uppercased() == "VN"
        || event.eventPlace == nil
        || Locale.current.regionCode?.uppercased() == "VN"
}

/// Detail uses this as a hard freshness check: a persisted `.unavailable` row is not trusted when
/// it has no display name, because GPS may have become available after a prior partial scan.
func eventNeedsPlaceResolution(_ event: PhotoEvent) -> Bool {
    event.placeResolutionState == .unresolved
        || event.primaryLocationLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        || needsVietnamesePlaceUpgrade(event)
}
