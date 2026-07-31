//
//  EventPhotoCurationServiceTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation
import SwiftData
import Testing
@testable import Nizi

/// Canned analyzer so these tests exercise `EventPhotoCurationService`'s orchestration (cache
/// validity, override preservation, persistence) without depending on real Vision output.
private final class StubEventPhotoAnalyzer: EventPhotoAnalyzer {
    var analyzedPhotos: [AnalyzedPhoto] = []
    var globalGroups: [String: String] = [:]

    func analyze(
        assets: [IndexedAsset],
        sessions: [PhotoSession],
        onProgress: @escaping (Int, Int) -> Void
    ) async -> [AnalyzedPhoto] {
        onProgress(1, 1)
        return analyzedPhotos
    }

    func globalDuplicateGroups(candidateAssetIDs: [String], similarityThreshold: Float) -> [String: String] {
        globalGroups.filter { candidateAssetIDs.contains($0.key) }
    }
}

struct EventPhotoCurationServiceTests {
    private func makeStore() throws -> SwiftDataMemoryDiscoveryStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
            MDEventCurationResult.self, MDPhotoCurationGroup.self, MDPhotoCurationItem.self,
            configurations: configuration
        )
        return SwiftDataMemoryDiscoveryStore(modelContainer: container)
    }

    private func analyzedPhoto(id: String, sessionID: UUID, minutesFromReference: Double, clusterID: String) -> AnalyzedPhoto {
        AnalyzedPhoto(
            assetID: id,
            sessionID: sessionID,
            creationDate: Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(minutesFromReference * 60),
            metrics: PhotoQualityMetrics(sharpness: 0.8, exposure: 0.8, faceScore: 0.5, isFavorite: false),
            similarityClusterID: clusterID
        )
    }

    // MARK: - § 47 — user overrides survive a forced recurate

    @Test func userOverridesSurviveForcedRecurateRegardlessOfNewAlgorithmProposal() async throws {
        let store = try makeStore()
        let event = PhotoEvent.fixtureForServiceTests(assetIDs: ["a", "b"])
        let sessionID = event.sessionIDs[0]

        let analyzer = StubEventPhotoAnalyzer()
        analyzer.analyzedPhotos = [
            analyzedPhoto(id: "a", sessionID: sessionID, minutesFromReference: 0, clusterID: "a"),
            analyzedPhoto(id: "b", sessionID: sessionID, minutesFromReference: 5, clusterID: "b")
        ]

        let service = EventPhotoCurationService(
            assetRepository: store, sessionRepository: store, curationRepository: store, analyzer: analyzer
        )

        let first = try await service.curate(event: event) { _, _ in }
        let itemA = try #require(first.groups.flatMap(\.items).first { $0.assetID == "a" })
        let itemB = try #require(first.groups.flatMap(\.items).first { $0.assetID == "b" })

        // Manual overrides: user explicitly removes "a" and explicitly adds/confirms "b".
        try await store.updateItemSelection(itemID: itemA.id, isSelected: false, source: .userRemoved)
        try await store.updateItemSelection(itemID: itemB.id, isSelected: true, source: .userAdded)

        // A forced recurate — same canned analyzer output, so the "fresh" algorithm run would,
        // left alone, reproduce the exact same (unoverridden) selection it made the first time.
        let recurated = try await service.curate(event: event, forceRecurate: true) { _, _ in }

        let itemsByAssetID = Dictionary(uniqueKeysWithValues: recurated.groups.flatMap(\.items).map { ($0.assetID, $0) })
        #expect(itemsByAssetID["a"]?.isSelected == false)
        #expect(itemsByAssetID["a"]?.selectionSource == .userRemoved)
        #expect(itemsByAssetID["b"]?.isSelected == true)
        #expect(itemsByAssetID["b"]?.selectionSource == .userAdded)
    }

    // MARK: - § 48 — asset fingerprint invalidates cache on same-count-different-membership

    @Test func assetFingerprintInvalidatesCacheOnSameCountDifferentMembers() {
        let result = EventCurationResult.fixtureWithFingerprint(assetIDs: ["a", "b", "c"])
        let eventWithDifferentMember = PhotoEvent.fixtureForServiceTests(assetIDs: ["a", "b", "d"])

        #expect(!EventPhotoCurationService.isCacheValid(result, for: eventWithDifferentMember))
    }

    @Test func cacheValidWhenFingerprintAlgorithmVersionAndStatusAllMatch() {
        let assetIDs = ["a", "b", "c"]
        let result = EventCurationResult.fixtureWithFingerprint(assetIDs: assetIDs)
        let event = PhotoEvent.fixtureForServiceTests(assetIDs: assetIDs)

        #expect(EventPhotoCurationService.isCacheValid(result, for: event))
    }
}

private extension PhotoEvent {
    static func fixtureForServiceTests(assetIDs: [String]) -> PhotoEvent {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return PhotoEvent(
            id: UUID(),
            titleSuggestion: "Test Event",
            startDate: now,
            endDate: now,
            primaryLocationLabel: nil,
            eventType: .dayEvent,
            score: 0.5,
            status: .new,
            sessionIDs: [UUID()],
            assetIDs: assetIDs,
            coverAssetID: assetIDs.first,
            discoveryReasons: [],
            algorithmVersion: 1,
            createdAt: now,
            updatedAt: now
        )
    }
}

private extension EventCurationResult {
    static func fixtureWithFingerprint(assetIDs: [String]) -> EventCurationResult {
        let now = Date()
        let items = assetIDs.enumerated().map { index, assetID in
            PhotoCurationItem(
                id: UUID(), assetID: assetID, sortOrder: index, qualityScore: 50,
                similarityClusterID: assetID, isSuggested: true, isSelected: true, selectionSource: .systemSuggested
            )
        }
        let group = PhotoCurationGroup(id: UUID(), sessionID: nil, startDate: now, endDate: now, sortOrder: 0, items: items)
        return EventCurationResult(
            photoEventID: UUID(),
            status: .completed,
            algorithmVersion: EventPhotoCurationService.algorithmVersion,
            createdAt: now,
            updatedAt: now,
            completedAt: now,
            sourceAssetCount: assetIDs.count,
            sourceAssetFingerprint: SourceAssetFingerprint.compute(assetIDs: assetIDs),
            errorMessage: nil,
            groups: [group]
        )
    }
}
