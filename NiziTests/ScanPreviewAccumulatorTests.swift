//
//  ScanPreviewAccumulatorTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation
import Testing
@testable import Nizi

struct ScanPreviewAccumulatorTests {
    private static let reference = ISO8601DateFormatter().date(from: "2024-01-01T08:00:00Z")!

    private func makeRecord(
        id: String,
        daysFromReference: Double,
        isFavorite: Bool = false,
        isScreenshot: Bool = false,
        isHidden: Bool = false
    ) -> PhotoAssetRecord {
        let date = Self.reference.addingTimeInterval(daysFromReference * 86400)
        return PhotoAssetRecord(
            id: id, creationDate: date, modificationDate: date, mediaType: .image,
            pixelWidth: 100, pixelHeight: 100, duration: 0, latitude: nil, longitude: nil,
            isFavorite: isFavorite, isHidden: isHidden, isScreenshot: isScreenshot,
            burstIdentifier: nil, sourceType: .userLibrary
        )
    }

    @Test func yearChangeResetsCandidateBuffer() {
        let firstYearBatch = [makeRecord(id: "a", daysFromReference: 0)]
        let state1 = ScanPreviewAccumulator.reduce(previous: .empty, batch: firstYearBatch)
        #expect(state1.candidates.map(\.assetID) == ["a"])

        // 2024 is a leap year — 366 days later lands cleanly in 2025.
        let nextYearBatch = [makeRecord(id: "b", daysFromReference: 366)]
        let state2 = ScanPreviewAccumulator.reduce(previous: state1, batch: nextYearBatch)

        #expect(state2.currentYear == (state1.currentYear ?? 0) + 1)
        #expect(state2.candidates.map(\.assetID) == ["b"])
    }

    @Test func favoritesAlwaysKeptEvenBeyondCap() {
        let config = ScanPreviewConfig(maxCandidates: 3)
        var batch = (0..<5).map { makeRecord(id: "plain-\($0)", daysFromReference: 0) }
        batch.append(makeRecord(id: "fav-1", daysFromReference: 0, isFavorite: true))
        batch.append(makeRecord(id: "fav-2", daysFromReference: 0, isFavorite: true))

        let state = ScanPreviewAccumulator.reduce(previous: .empty, batch: batch, config: config)

        #expect(state.candidates.count == 3)
        #expect(state.candidates.filter(\.isFavorite).count == 2)
        #expect(state.candidates.contains { $0.assetID == "fav-1" })
        #expect(state.candidates.contains { $0.assetID == "fav-2" })
    }

    @Test func capRespectedForPlainPhotos() {
        let config = ScanPreviewConfig(maxCandidates: 4)
        let batch = (0..<10).map { makeRecord(id: "plain-\($0)", daysFromReference: 0) }

        let state = ScanPreviewAccumulator.reduce(previous: .empty, batch: batch, config: config)

        #expect(state.candidates.count == 4)
    }

    @Test func screenshotsAndHiddenExcluded() {
        let batch = [
            makeRecord(id: "shot", daysFromReference: 0, isScreenshot: true),
            makeRecord(id: "hidden", daysFromReference: 0, isHidden: true),
            makeRecord(id: "ok", daysFromReference: 0)
        ]

        let state = ScanPreviewAccumulator.reduce(previous: .empty, batch: batch)

        #expect(state.candidates.map(\.assetID) == ["ok"])
    }

    @Test func sameInputProducesSameOutput() {
        let batch = (0..<5).map { makeRecord(id: "asset-\($0)", daysFromReference: 0, isFavorite: $0 == 0) }
        let first = ScanPreviewAccumulator.reduce(previous: .empty, batch: batch)
        let second = ScanPreviewAccumulator.reduce(previous: .empty, batch: batch)
        #expect(first == second)
    }
}
