//
//  SwiftDataMemoryDiscoveryStoreTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation
import SwiftData
import Testing
@testable import Nizi

struct SwiftDataMemoryDiscoveryStoreTests {
    private func makeStore() throws -> SwiftDataMemoryDiscoveryStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
            MDEventCurationResult.self, MDPhotoCurationGroup.self, MDPhotoCurationItem.self,
            configurations: configuration
        )
        return SwiftDataMemoryDiscoveryStore(modelContainer: container)
    }

    @Test func upsertIsIdempotent() async throws {
        let store = try makeStore()
        let record = PhotoAssetRecord.fixture(id: "asset-1")

        _ = try await store.upsert([record])
        _ = try await store.upsert([record])

        let total = try await store.totalIndexedCount()
        #expect(total == 1)
    }

    @Test func upsertUpdatesExistingRecord() async throws {
        let store = try makeStore()
        let original = PhotoAssetRecord.fixture(id: "asset-1", isFavorite: false)
        let updated = PhotoAssetRecord.fixture(id: "asset-1", isFavorite: true)

        _ = try await store.upsert([original])
        let result = try await store.upsert([updated])

        #expect(result.succeededCount == 1)
        #expect(try await store.totalIndexedCount() == 1)
    }

    @Test func checkpointRoundTrips() async throws {
        let store = try makeStore()
        var checkpoint = ScanCheckpoint.newInitial()
        checkpoint.processedCount = 42
        checkpoint.cursorOffset = 42
        checkpoint.status = .running

        try await store.save(checkpoint)
        let loaded = try await store.checkpoint(for: .initial)

        #expect(loaded?.processedCount == 42)
        #expect(loaded?.cursorOffset == 42)
        #expect(loaded?.status == .running)
    }

    @Test func clearAllRemovesAssetsAndCheckpoint() async throws {
        let store = try makeStore()
        _ = try await store.upsert([.fixture(id: "asset-1")])
        try await store.save(.newInitial())

        try await store.clearAll()

        #expect(try await store.totalIndexedCount() == 0)
        #expect(try await store.checkpoint(for: .initial) == nil)
    }

    @Test func yearMonthStatisticsGroupsByCreationDate() async throws {
        let store = try makeStore()
        var components = DateComponents()
        components.year = 2024
        components.month = 6
        components.day = 10
        let date = Calendar.current.date(from: components)!

        _ = try await store.upsert([
            .fixture(id: "asset-1", creationDate: date),
            .fixture(id: "asset-2", creationDate: date)
        ])

        let stats = try await store.yearMonthStatistics()
        #expect(stats.count == 1)
        #expect(stats.first?.year == 2024)
        #expect(stats.first?.month == 6)
        #expect(stats.first?.count == 2)
    }

    @Test func fetchClusterableAssetsExcludesAssetsWithoutCreationDate() async throws {
        let store = try makeStore()
        _ = try await store.upsert([
            .fixture(id: "asset-dated"),
            PhotoAssetRecord(
                id: "asset-undated",
                creationDate: nil,
                modificationDate: nil,
                mediaType: .image,
                pixelWidth: 100,
                pixelHeight: 100,
                duration: 0,
                latitude: nil,
                longitude: nil,
                isFavorite: false,
                isHidden: false,
                isScreenshot: false,
                burstIdentifier: nil,
                sourceType: .userLibrary
            )
        ])

        let clusterable = try await store.fetchClusterableAssets()
        #expect(clusterable.map(\.id) == ["asset-dated"])
    }

    @Test func rebuildDoesNotAccumulateDuplicateEvents() async throws {
        let store = try makeStore()
        let firstRun = [PhotoEvent.fixture(status: .new), PhotoEvent.fixture(status: .new)]
        try await store.replaceRebuildableEvents(firstRun)
        #expect(try await store.fetchEvents(sortedBy: .scoreDescending).count == 2)

        // Rebuilds always mint fresh IDs (new UUIDs), simulating a re-run of discovery.
        let secondRun = [PhotoEvent.fixture(status: .new), PhotoEvent.fixture(status: .new)]
        try await store.replaceRebuildableEvents(secondRun)

        #expect(try await store.fetchEvents(sortedBy: .scoreDescending).count == 2)
    }

    @Test func rebuildPreservesAcceptedAndConvertedEvents() async throws {
        let store = try makeStore()
        let accepted = PhotoEvent.fixture(status: .accepted)
        try await store.replaceRebuildableEvents([accepted, .fixture(status: .new)])

        try await store.replaceRebuildableEvents([.fixture(status: .new)])

        let remaining = try await store.fetchEvents(sortedBy: .scoreDescending)
        #expect(remaining.contains { $0.id == accepted.id })
        #expect(remaining.count == 2)
    }

    @Test func lovedEventPersistsAndFetchesNewestFirst() async throws {
        let store = try makeStore()
        let older = PhotoEvent.fixture(status: .new, startDate: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = PhotoEvent.fixture(status: .new, startDate: Date(timeIntervalSince1970: 1_710_000_000))
        try await store.replaceRebuildableEvents([older, newer])

        try await store.setEventLoved(eventID: older.id, isLoved: true)
        try await store.setEventLoved(eventID: newer.id, isLoved: true)

        let loved = try await store.fetchLovedEvents()
        #expect(loved.map(\.id) == [newer.id, older.id])
        #expect(loved.allSatisfy { $0.isLoved })
    }

    @Test func rebuildPreservesLoveForAnEventWithTheSameAssets() async throws {
        let store = try makeStore()
        let original = PhotoEvent.fixture(status: .new, assetIDs: ["asset-a", "asset-b"])
        try await store.replaceRebuildableEvents([original])
        try await store.setEventLoved(eventID: original.id, isLoved: true)

        let rebuilt = PhotoEvent.fixture(status: .new, assetIDs: ["asset-b", "asset-a"])
        try await store.replaceRebuildableEvents([rebuilt])

        let loved = try await store.fetchLovedEvents()
        #expect(loved.map(\.id) == [rebuilt.id])
        #expect(loved.first?.isLoved == true)
    }

    @Test func deletingEventDoesNotDeleteItsLibraryAssetRecords() async throws {
        let store = try makeStore()
        let event = PhotoEvent.fixture(status: .new, assetIDs: ["asset-kept"])
        _ = try await store.upsert([.fixture(id: "asset-kept")])
        try await store.replaceRebuildableEvents([event])

        try await store.deleteEvent(id: event.id)

        #expect(try await store.fetchEvents(sortedBy: .newestFirst).isEmpty)
        #expect(try await store.fetchAssets(ids: ["asset-kept"]).map(\.id) == ["asset-kept"])
    }

    @Test func mergingEventsCombinesAssetsAndSessionsIntoDestination() async throws {
        let store = try makeStore()
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_710_000_000)
        let sourceSession = UUID()
        let destinationSession = UUID()
        let source = PhotoEvent.fixture(status: .new, startDate: older, sessionIDs: [sourceSession], assetIDs: ["a", "shared"])
        let destination = PhotoEvent.fixture(status: .new, startDate: newer, sessionIDs: [destinationSession], assetIDs: ["shared", "b"])
        try await store.replaceRebuildableEvents([source, destination])

        try await store.mergeEvent(sourceID: source.id, into: destination.id)

        let events = try await store.fetchEvents(sortedBy: .newestFirst)
        let merged = try #require(events.first)
        #expect(events.count == 1)
        #expect(merged.id == destination.id)
        #expect(merged.startDate == older)
        #expect(merged.endDate == newer)
        #expect(merged.sessionIDs == [destinationSession, sourceSession])
        #expect(merged.assetIDs == ["shared", "b", "a"])
    }

    @Test func curationResultRoundTripsGroupsAndItems() async throws {
        let store = try makeStore()
        let eventID = UUID()
        let result = EventCurationResult.fixture(photoEventID: eventID)

        try await store.saveResult(result)
        let loaded = try await store.result(for: eventID)

        #expect(loaded?.status == .completed)
        #expect(loaded?.groups.count == result.groups.count)
        #expect(loaded?.selectedAssetCount == result.selectedAssetCount)
        #expect(loaded?.orderedSelectedAssetIdentifiers == result.orderedSelectedAssetIdentifiers)
    }

    @Test func updateItemSelectionPersistsWithoutRewritingTheWholeResult() async throws {
        let store = try makeStore()
        let eventID = UUID()
        let result = EventCurationResult.fixture(photoEventID: eventID)
        try await store.saveResult(result)

        let firstItem = try #require(result.groups.first?.items.first)
        #expect(firstItem.isSelected == false)

        try await store.updateItemSelection(itemID: firstItem.id, isSelected: true, source: .userAdded)

        let reloaded = try await store.result(for: eventID)
        let reloadedItem = reloaded?.groups.first?.items.first { $0.id == firstItem.id }
        #expect(reloadedItem?.isSelected == true)
        #expect(reloadedItem?.selectionSource == .userAdded)
    }

    /// Photo Editor's Event "save as new asset" flow (`PhotoAssetExporting`) exports a brand-new
    /// `PHAsset` for whichever photo was just edited — `updateItemAsset` is how the curation item
    /// that used to point at the original asset gets swapped over to it.
    @Test func updateItemAssetPersistsWithoutRewritingTheWholeResult() async throws {
        let store = try makeStore()
        let eventID = UUID()
        let result = EventCurationResult.fixture(photoEventID: eventID)
        try await store.saveResult(result)

        let firstItem = try #require(result.groups.first?.items.first)
        let originalAssetID = firstItem.assetID

        try await store.updateItemAsset(itemID: firstItem.id, newAssetLocalIdentifier: "new-asset-after-edit")

        let reloaded = try await store.result(for: eventID)
        let reloadedItem = reloaded?.groups.first?.items.first { $0.id == firstItem.id }
        #expect(reloadedItem?.assetID == "new-asset-after-edit")
        #expect(reloadedItem?.assetID != originalAssetID)
        // Everything else about the item stays untouched by the swap.
        #expect(reloadedItem?.isSelected == firstItem.isSelected)
        #expect(reloadedItem?.sortOrder == firstItem.sortOrder)
    }

    @Test func clearResultRemovesGroupsAndItemsToo() async throws {
        let store = try makeStore()
        let eventID = UUID()
        try await store.saveResult(.fixture(photoEventID: eventID))

        try await store.clearResult(for: eventID)

        #expect(try await store.result(for: eventID) == nil)
    }

    @Test func markStatusCreatesAResultRowWhenNoneExists() async throws {
        let store = try makeStore()
        let eventID = UUID()

        try await store.markStatus(photoEventID: eventID, status: .processing, errorMessage: nil)

        let loaded = try await store.result(for: eventID)
        #expect(loaded?.status == .processing)
    }

    @Test func clearAllAlsoRemovesCurationResults() async throws {
        let store = try makeStore()
        let eventID = UUID()
        try await store.saveResult(.fixture(photoEventID: eventID))

        try await store.clearAll()

        #expect(try await store.result(for: eventID) == nil)
    }
}

private extension PhotoAssetRecord {
    static func fixture(
        id: String,
        creationDate: Date = Date(),
        isFavorite: Bool = false
    ) -> PhotoAssetRecord {
        PhotoAssetRecord(
            id: id,
            creationDate: creationDate,
            modificationDate: nil,
            mediaType: .image,
            pixelWidth: 100,
            pixelHeight: 100,
            duration: 0,
            latitude: nil,
            longitude: nil,
            isFavorite: isFavorite,
            isHidden: false,
            isScreenshot: false,
            burstIdentifier: nil,
            sourceType: .userLibrary
        )
    }
}

private extension EventCurationResult {
    static func fixture(photoEventID: UUID) -> EventCurationResult {
        let now = Date()
        let groupID = UUID()
        let items = [
            PhotoCurationItem(
                id: UUID(), assetID: "asset-1", sortOrder: 0, qualityScore: 80,
                similarityClusterID: "asset-1", isSuggested: false, isSelected: false, selectionSource: .systemSuggested
            ),
            PhotoCurationItem(
                id: UUID(), assetID: "asset-2", sortOrder: 1, qualityScore: 90,
                similarityClusterID: "asset-2", isSuggested: true, isSelected: true, selectionSource: .systemSuggested
            )
        ]
        let group = PhotoCurationGroup(
            id: groupID, sessionID: UUID(), startDate: now, endDate: now, sortOrder: 0, items: items
        )
        return EventCurationResult(
            photoEventID: photoEventID,
            status: .completed,
            algorithmVersion: 1,
            createdAt: now,
            updatedAt: now,
            completedAt: now,
            sourceAssetCount: 2,
            errorMessage: nil,
            groups: [group]
        )
    }
}

private extension PhotoEvent {
    static func fixture(
        status: PhotoEventStatus,
        startDate: Date = Date(),
        sessionIDs: [UUID] = [UUID()],
        assetIDs: [String] = ["asset-1", "asset-2"]
    ) -> PhotoEvent {
        let now = startDate
        return PhotoEvent(
            id: UUID(),
            titleSuggestion: "10/06/2024",
            startDate: startDate,
            endDate: now,
            primaryLocationLabel: nil,
            eventType: .dayEvent,
            score: 0.5,
            status: status,
            sessionIDs: sessionIDs,
            assetIDs: assetIDs,
            coverAssetID: assetIDs.first,
            discoveryReasons: [DiscoveryReason(kind: .assetCountOverDuration, text: "2 ảnh trong ngày")],
            algorithmVersion: 1,
            createdAt: now,
            updatedAt: now
        )
    }
}
