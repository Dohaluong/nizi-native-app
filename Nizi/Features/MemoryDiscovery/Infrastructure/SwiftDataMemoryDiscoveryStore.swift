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
actor SwiftDataMemoryDiscoveryStore: LocalAssetRepository, ScanCheckpointRepository, PhotoSessionRepository, PhotoEventRepository, EventCurationRepository {
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
        for model in existing where !committedStatuses.contains(model.status) {
            modelContext.delete(model)
        }

        for event in events {
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
                        selectionSource: SelectionSource(rawValue: itemModel.selectionSource) ?? .systemSuggested
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
}
