//
//  SwiftDataMemoryDiscoveryStore.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation
import SwiftData

/// Background-safe SwiftData repository for the Local Memory Index.
/// `@ModelActor` gives this its own isolated `ModelContext`, so batch scanning never
/// touches the main actor's context and can't freeze the UI.
@ModelActor
actor SwiftDataMemoryDiscoveryStore: LocalAssetRepository, ScanCheckpointRepository, PhotoSessionRepository, PhotoEventRepository, EventCurationRepository, MemoryCandidateRepository, LocationIntelligenceRepository, PhotoTripRepository {
    // MARK: LocalAssetRepository

    @discardableResult
    func upsert(_ records: [PhotoAssetRecord]) async throws -> UpsertResult {
        let now = Date()
        var succeeded = 0
        var failed = 0

        for record in records {
            do {
                let identifier = record.id
                var descriptor = FetchDescriptor<MDLocalAsset>(
                    predicate: #Predicate { $0.assetLocalIdentifier == identifier }
                )
                descriptor.fetchLimit = 1

                if let existing = try modelContext.fetch(descriptor).first {
                    existing.apply(record, now: now)
                } else {
                    modelContext.insert(MDLocalAsset(record: record, now: now))
                }
                succeeded += 1
            } catch {
                failed += 1
                NiziLogger.discovery.error("local_asset_upsert_failed")
            }
        }

        try modelContext.save()
        return UpsertResult(succeededCount: succeeded, failedCount: failed)
    }

    func yearMonthStatistics() async throws -> [YearMonthCount] {
        let assets = try modelContext.fetch(FetchDescriptor<MDLocalAsset>())
        let calendar = Calendar.current

        var counts: [String: (year: Int, month: Int, count: Int)] = [:]
        for asset in assets {
            guard let date = asset.creationDate else { continue }
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let year = components.year, let month = components.month else { continue }
            let key = "\(year)-\(month)"
            counts[key, default: (year, month, 0)].count += 1
        }

        return counts.values
            .map { YearMonthCount(year: $0.year, month: $0.month, count: $0.count) }
            .sorted { ($0.year, $0.month) > ($1.year, $1.month) }
    }

    func totalIndexedCount() async throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<MDLocalAsset>())
    }

    func fetchClusterableAssets() async throws -> [IndexedAsset] {
        let availableRaw = AssetAvailabilityStatus.available.rawValue
        let indexedRaw = AssetDiscoveryStatus.indexed.rawValue
        // Hidden photos never contribute to event discovery — see docs/sprint/SPRINT-005B-TODO.md
        // item 7. Screenshots stay eligible here (a screenshot-only cluster is still rejected
        // downstream in `EventDiscoveryEngine.buildEvent`); excluding them from curated
        // *selection* specifically happens in `EventPhotoCurationEngine`.
        let descriptor = FetchDescriptor<MDLocalAsset>(
            predicate: #Predicate { asset in
                asset.availabilityStatus == availableRaw
                    && asset.discoveryStatus == indexedRaw
                    && asset.creationDate != nil
                    && asset.hidden == false
            },
            sortBy: [SortDescriptor(\.creationDate)]
        )
        return try modelContext.fetch(descriptor).compactMap { model in
            guard let creationDate = model.creationDate else { return nil }
            return IndexedAsset(
                id: model.assetLocalIdentifier,
                creationDate: creationDate,
                latitude: model.latitude,
                longitude: model.longitude,
                isFavorite: model.favorite,
                isScreenshot: model.screenshot,
                burstIdentifier: model.burstIdentifier,
                mediaType: PhotoMediaType(rawValue: model.mediaType) ?? .unknown
            )
        }
    }

    func fetchAssets(ids: [String]) async throws -> [IndexedAsset] {
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<MDLocalAsset>(
            predicate: #Predicate { idSet.contains($0.assetLocalIdentifier) }
        )
        return try modelContext.fetch(descriptor).compactMap { model in
            guard let creationDate = model.creationDate else { return nil }
            return IndexedAsset(
                id: model.assetLocalIdentifier,
                creationDate: creationDate,
                latitude: model.latitude,
                longitude: model.longitude,
                isFavorite: model.favorite,
                isScreenshot: model.screenshot,
                burstIdentifier: model.burstIdentifier,
                mediaType: PhotoMediaType(rawValue: model.mediaType) ?? .unknown
            )
        }
    }

    func clearAll() async throws {
        try modelContext.delete(model: MDLocalAsset.self)
        try modelContext.delete(model: MDScanCheckpoint.self)
        try modelContext.delete(model: MDPhotoSession.self)
        try modelContext.delete(model: MDEventCandidate.self)
        try modelContext.delete(model: MDEventCurationResult.self)
        try modelContext.delete(model: MDPhotoCurationGroup.self)
        try modelContext.delete(model: MDPhotoCurationItem.self)
        try modelContext.delete(model: MDMemoryCandidate.self)
        try modelContext.delete(model: MDLocationCluster.self)
        try modelContext.delete(model: MDHomeAnchor.self)
        try modelContext.delete(model: MDFamiliarPlace.self)
        try modelContext.delete(model: MDPhotoTrip.self)
        try modelContext.save()
    }

    // MARK: ScanCheckpointRepository

    func checkpoint(for scanType: ScanType) async throws -> ScanCheckpoint? {
        let rawType = scanType.rawValue
        var descriptor = FetchDescriptor<MDScanCheckpoint>(
            predicate: #Predicate { $0.scanType == rawType }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(ScanCheckpoint.init)
    }

    func save(_ checkpoint: ScanCheckpoint) async throws {
        let rawType = checkpoint.scanType.rawValue
        var descriptor = FetchDescriptor<MDScanCheckpoint>(
            predicate: #Predicate { $0.scanType == rawType }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(checkpoint)
        } else {
            modelContext.insert(MDScanCheckpoint(checkpoint: checkpoint))
        }
        try modelContext.save()
    }

    func clear(_ scanType: ScanType) async throws {
        let rawType = scanType.rawValue
        try modelContext.delete(model: MDScanCheckpoint.self, where: #Predicate { $0.scanType == rawType })
        try modelContext.save()
    }

    // MARK: PhotoSessionRepository

    func replaceRebuildableSessions(_ sessions: [PhotoSession]) async throws {
        try modelContext.delete(model: MDPhotoSession.self)
        let now = Date()
        for session in sessions {
            modelContext.insert(MDPhotoSession(session: session, now: now))
        }
        try modelContext.save()
    }

    func fetchSessions(ids: [UUID]) async throws -> [PhotoSession] {
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<MDPhotoSession>(
            predicate: #Predicate { idSet.contains($0.sessionID) }
        )
        return try modelContext.fetch(descriptor).map(PhotoSession.init)
    }

    // MARK: PhotoEventRepository

    func replaceRebuildableEvents(_ events: [PhotoEvent]) async throws {
        let committedStatuses: Set<String> = [
            PhotoEventStatus.accepted.rawValue,
            PhotoEventStatus.convertedToAlbum.rawValue
        ]
        let existing = try modelContext.fetch(FetchDescriptor<MDEventCandidate>())
        // Event discovery deliberately mints fresh IDs. Preserve the one user-owned state this
        // flow stores by matching an otherwise identical event's asset membership before old
        // rebuildable rows are removed. This is intentionally a narrow bridge, not stable Event
        // identity: changed cluster membership will not match and needs a future identity sprint.
        let lovedAssetKeys = Set(existing.filter(\.isLoved).map { eventAssetKey($0.assetIdentifiers) })
        for model in existing where !committedStatuses.contains(model.status) {
            modelContext.delete(model)
        }

        for var event in events {
            if lovedAssetKeys.contains(eventAssetKey(event.assetIDs)) {
                event.isLoved = true
            }
            modelContext.insert(MDEventCandidate(event: event))
        }
        try modelContext.save()
    }

    func fetchEvents(sortedBy order: PhotoEventSortOrder) async throws -> [PhotoEvent] {
        let descriptor: FetchDescriptor<MDEventCandidate>
        switch order {
        case .scoreDescending:
            descriptor = FetchDescriptor(sortBy: [SortDescriptor(\.score, order: .reverse)])
        case .newestFirst:
            descriptor = FetchDescriptor(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        }
        return try modelContext.fetch(descriptor).map(PhotoEvent.init)
    }

    func fetchLovedEvents() async throws -> [PhotoEvent] {
        let descriptor = FetchDescriptor<MDEventCandidate>(
            predicate: #Predicate { $0.isLoved },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(PhotoEvent.init)
    }

    func setEventLoved(eventID: UUID, isLoved: Bool) async throws {
        var descriptor = FetchDescriptor<MDEventCandidate>(predicate: #Predicate { $0.candidateID == eventID })
        descriptor.fetchLimit = 1
        guard let event = try modelContext.fetch(descriptor).first else { return }
        event.isLoved = isLoved
        event.updatedAt = Date()
        try modelContext.save()
    }

    func setEventPlace(eventID: UUID, place: EventPlace?, state: EventPlaceResolutionState) async throws {
        var descriptor = FetchDescriptor<MDEventCandidate>(predicate: #Predicate { $0.candidateID == eventID })
        descriptor.fetchLimit = 1
        guard let event = try modelContext.fetch(descriptor).first else { return }
        event.placeLatitude = place?.coordinate.latitude
        event.placeLongitude = place?.coordinate.longitude
        event.placeSubLocality = place?.subLocality
        event.placeLocality = place?.locality
        event.placeSubAdministrativeArea = place?.subAdministrativeArea
        event.placeAdministrativeArea = place?.administrativeArea
        event.placeCountry = place?.country
        event.placeCountryCode = place?.countryCode
        event.placeDisplayName = place?.displayName
        event.primaryLocationLabel = place?.displayName
        event.placeResolutionState = state.rawValue
        event.placeResolvedAt = place == nil ? nil : Date()
        event.updatedAt = Date()
        try modelContext.save()
    }

    func deleteEvent(id: UUID) async throws {
        try deleteCurationData(for: id)
        try modelContext.delete(model: MDEventCandidate.self, where: #Predicate { $0.candidateID == id })
        try modelContext.save()
    }

    func mergeEvent(sourceID: UUID, into destinationID: UUID) async throws {
        guard sourceID != destinationID else { return }

        var sourceDescriptor = FetchDescriptor<MDEventCandidate>(predicate: #Predicate { $0.candidateID == sourceID })
        sourceDescriptor.fetchLimit = 1
        var destinationDescriptor = FetchDescriptor<MDEventCandidate>(predicate: #Predicate { $0.candidateID == destinationID })
        destinationDescriptor.fetchLimit = 1

        guard
            let source = try modelContext.fetch(sourceDescriptor).first,
            let destination = try modelContext.fetch(destinationDescriptor).first
        else { return }

        destination.startDate = min(destination.startDate, source.startDate)
        destination.endDate = max(destination.endDate, source.endDate)
        destination.sessionIdentifiers = orderedUnique(destination.sessionIdentifiers + source.sessionIdentifiers)
        destination.assetIdentifiers = orderedUnique(destination.assetIdentifiers + source.assetIdentifiers)
        destination.coverAssetID = destination.coverAssetID ?? source.coverAssetID
        // The dominant coordinate can change after combining two Events. Discard both stale
        // place snapshots and let the visible merged card lazily resolve from its new asset set.
        destination.primaryLocationLabel = nil
        destination.placeLatitude = nil
        destination.placeLongitude = nil
        destination.placeSubLocality = nil
        destination.placeLocality = nil
        destination.placeSubAdministrativeArea = nil
        destination.placeAdministrativeArea = nil
        destination.placeCountry = nil
        destination.placeCountryCode = nil
        destination.placeDisplayName = nil
        destination.placeResolutionState = EventPlaceResolutionState.unresolved.rawValue
        destination.placeResolvedAt = nil
        destination.score = max(destination.score, source.score)
        destination.updatedAt = Date()

        // Curation rows are derived from the original Event membership. Once sessions/assets have
        // changed they cannot safely be reused, so remove them with the source Event as well.
        try deleteCurationData(for: sourceID)
        try deleteCurationData(for: destinationID)
        modelContext.delete(source)
        try modelContext.save()
    }

    private func deleteCurationData(for eventID: UUID) throws {
        try modelContext.delete(model: MDEventCurationResult.self, where: #Predicate { $0.eventCandidateID == eventID })
        try modelContext.delete(model: MDPhotoCurationGroup.self, where: #Predicate { $0.eventCandidateID == eventID })
        try modelContext.delete(model: MDPhotoCurationItem.self, where: #Predicate { $0.eventCandidateID == eventID })
    }

    private func orderedUnique<Element: Hashable>(_ values: [Element]) -> [Element] {
        var seen = Set<Element>()
        return values.filter { seen.insert($0).inserted }
    }

    private func eventAssetKey(_ assetIDs: [String]) -> String {
        assetIDs.sorted().joined(separator: "\u{1F}")
    }

    // MARK: EventCurationRepository

    func result(for photoEventID: UUID) async throws -> EventCurationResult? {
        var resultDescriptor = FetchDescriptor<MDEventCurationResult>(
            predicate: #Predicate { $0.eventCandidateID == photoEventID }
        )
        resultDescriptor.fetchLimit = 1
        guard let resultModel = try modelContext.fetch(resultDescriptor).first else { return nil }

        let groupDescriptor = FetchDescriptor<MDPhotoCurationGroup>(
            predicate: #Predicate { $0.eventCandidateID == photoEventID },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let groupModels = try modelContext.fetch(groupDescriptor)

        let itemDescriptor = FetchDescriptor<MDPhotoCurationItem>(
            predicate: #Predicate { $0.eventCandidateID == photoEventID },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let itemsByGroupID = Dictionary(grouping: try modelContext.fetch(itemDescriptor), by: \.groupID)

        let groups = groupModels.map { groupModel in
            PhotoCurationGroup(
                id: groupModel.id,
                sessionID: groupModel.sessionID,
                startDate: groupModel.startDate,
                endDate: groupModel.endDate,
                sortOrder: groupModel.sortOrder,
                items: (itemsByGroupID[groupModel.id] ?? []).map { itemModel in
                    PhotoCurationItem(
                        id: itemModel.id,
                        assetID: itemModel.assetLocalIdentifier,
                        sortOrder: itemModel.sortOrder,
                        qualityScore: itemModel.qualityScore,
                        similarityClusterID: itemModel.similarityClusterIdentifier,
                        isSuggested: itemModel.isSuggested,
                        isSelected: itemModel.isSelected,
                        selectionSource: SelectionSource(rawValue: itemModel.selectionSource) ?? .systemSuggested,
                        rejectionReason: itemModel.rejectionReason.flatMap(CurationRejectionReason.init(rawValue:))
                    )
                }
            )
        }

        return EventCurationResult(
            photoEventID: resultModel.eventCandidateID,
            status: CurationStatus(rawValue: resultModel.status) ?? .notStarted,
            algorithmVersion: resultModel.algorithmVersion,
            createdAt: resultModel.createdAt,
            updatedAt: resultModel.updatedAt,
            completedAt: resultModel.completedAt,
            sourceAssetCount: resultModel.sourceAssetCount,
            sourceAssetFingerprint: resultModel.sourceAssetFingerprint,
            errorMessage: resultModel.errorMessage,
            groups: groups
        )
    }

    func saveResult(_ result: EventCurationResult) async throws {
        try await clearResult(for: result.photoEventID)

        let resultModel = MDEventCurationResult(
            eventCandidateID: result.photoEventID,
            status: result.status,
            algorithmVersion: result.algorithmVersion,
            now: result.createdAt
        )
        resultModel.updatedAt = result.updatedAt
        resultModel.completedAt = result.completedAt
        resultModel.sourceAssetCount = result.sourceAssetCount
        resultModel.sourceAssetFingerprint = result.sourceAssetFingerprint
        resultModel.errorMessage = result.errorMessage
        modelContext.insert(resultModel)

        for group in result.groups {
            modelContext.insert(MDPhotoCurationGroup(group: group, eventCandidateID: result.photoEventID))
            for item in group.items {
                modelContext.insert(MDPhotoCurationItem(item: item, groupID: group.id, eventCandidateID: result.photoEventID))
            }
        }

        try modelContext.save()
    }

    func updateItemSelection(itemID: UUID, isSelected: Bool, source: SelectionSource) async throws {
        var descriptor = FetchDescriptor<MDPhotoCurationItem>(predicate: #Predicate { $0.id == itemID })
        descriptor.fetchLimit = 1
        guard let item = try modelContext.fetch(descriptor).first else { return }
        item.isSelected = isSelected
        item.selectionSource = source.rawValue
        try modelContext.save()
    }

    func updateItemAsset(itemID: UUID, newAssetLocalIdentifier: String) async throws {
        var descriptor = FetchDescriptor<MDPhotoCurationItem>(predicate: #Predicate { $0.id == itemID })
        descriptor.fetchLimit = 1
        guard let item = try modelContext.fetch(descriptor).first else { return }
        item.assetLocalIdentifier = newAssetLocalIdentifier
        try modelContext.save()
    }

    func markStatus(photoEventID: UUID, status: CurationStatus, errorMessage: String?) async throws {
        var descriptor = FetchDescriptor<MDEventCurationResult>(
            predicate: #Predicate { $0.eventCandidateID == photoEventID }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.status = status.rawValue
            existing.errorMessage = errorMessage
            existing.updatedAt = Date()
        } else {
            let model = MDEventCurationResult(
                eventCandidateID: photoEventID,
                status: status,
                algorithmVersion: 0,
                now: Date()
            )
            model.errorMessage = errorMessage
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    func clearResult(for photoEventID: UUID) async throws {
        try modelContext.delete(model: MDEventCurationResult.self, where: #Predicate { $0.eventCandidateID == photoEventID })
        try modelContext.delete(model: MDPhotoCurationGroup.self, where: #Predicate { $0.eventCandidateID == photoEventID })
        try modelContext.delete(model: MDPhotoCurationItem.self, where: #Predicate { $0.eventCandidateID == photoEventID })
        try modelContext.save()
    }

    // MARK: MemoryCandidateRepository

    func save(_ candidate: MemoryCandidate) async throws {
        let targetID = candidate.id
        var descriptor = FetchDescriptor<MDMemoryCandidate>(
            predicate: #Predicate { $0.candidateID == targetID }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.eventID = candidate.eventID
            existing.title = candidate.title
            existing.subtitle = candidate.subtitle
            existing.startDate = candidate.startDate
            existing.endDate = candidate.endDate
            existing.placeName = candidate.placeName
            existing.coverAssetID = candidate.coverAssetID
            existing.selectedAssetIdentifiers = candidate.selectedAssetIDs
            existing.totalPhotoCount = candidate.totalPhotoCount
            existing.score = candidate.score
            existing.status = candidate.status.rawValue
            existing.updatedAt = candidate.updatedAt
        } else {
            modelContext.insert(MDMemoryCandidate(candidate: candidate))
        }
        try modelContext.save()
    }

    func fetchLatest() async throws -> MemoryCandidate? {
        var descriptor = FetchDescriptor<MDMemoryCandidate>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(MemoryCandidate.init)
    }

    func updateSelection(id: UUID, selectedAssetIDs: [String]) async throws {
        var descriptor = FetchDescriptor<MDMemoryCandidate>(predicate: #Predicate { $0.candidateID == id })
        descriptor.fetchLimit = 1
        guard let existing = try modelContext.fetch(descriptor).first else { return }
        existing.selectedAssetIdentifiers = selectedAssetIDs
        existing.totalPhotoCount = selectedAssetIDs.count
        existing.updatedAt = Date()
        try modelContext.save()
    }

    // MARK: LocationIntelligenceRepository

    func replaceLocationIntelligence(clusters: [LocationCluster], home: HomeAnchor?, familiarPlaces: [FamiliarPlace]) async throws {
        try modelContext.delete(model: MDLocationCluster.self)
        try modelContext.delete(model: MDFamiliarPlace.self)

        // Never silently overwrite a Home the user actually confirmed with a fresh algorithmic
        // guess — the Full Home Detector rebuild is allowed to touch everything else, but not this.
        let existingHomeIsUserConfirmed = try modelContext.fetch(FetchDescriptor<MDHomeAnchor>()).first?.source == HomeAnchorSource.userConfirmed.rawValue
        if !existingHomeIsUserConfirmed {
            try modelContext.delete(model: MDHomeAnchor.self)
            if let home {
                modelContext.insert(MDHomeAnchor(home: home))
            }
        }

        for cluster in clusters {
            modelContext.insert(MDLocationCluster(cluster: cluster))
        }
        for place in familiarPlaces {
            modelContext.insert(MDFamiliarPlace(place: place))
        }
        try modelContext.save()
    }

    func confirmUserHome(_ home: HomeAnchor) async throws {
        try modelContext.delete(model: MDHomeAnchor.self)
        var confirmed = home
        confirmed.source = .userConfirmed
        modelContext.insert(MDHomeAnchor(home: confirmed))
        try modelContext.save()
    }

    func fetchHome() async throws -> HomeAnchor? {
        var descriptor = FetchDescriptor<MDHomeAnchor>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(HomeAnchor.init)
    }

    func fetchFamiliarPlaces() async throws -> [FamiliarPlace] {
        try modelContext.fetch(FetchDescriptor<MDFamiliarPlace>())
            .map(FamiliarPlace.init)
            .sorted { $0.confidence > $1.confidence }
    }

    func fetchLocationClusters() async throws -> [LocationCluster] {
        try modelContext.fetch(FetchDescriptor<MDLocationCluster>()).map(LocationCluster.init)
    }

    // MARK: PhotoTripRepository

    func replaceRebuildableTrips(_ trips: [PhotoTrip]) async throws {
        try modelContext.delete(model: MDPhotoTrip.self)
        for trip in trips {
            modelContext.insert(MDPhotoTrip(trip: trip))
        }
        try modelContext.save()
    }

    func fetchTrips() async throws -> [PhotoTrip] {
        let descriptor = FetchDescriptor<MDPhotoTrip>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        return try modelContext.fetch(descriptor).map(PhotoTrip.init)
    }
}
