//
//  AlbumSpreadBuilderTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

struct AlbumSpreadBuilderTests {
    private func photo(id: String, eventId: String, hourOffset: Int) -> AlbumPlanningPhoto {
        let base = DateComponents(calendar: .current, year: 2026, month: 1, day: 1).date!
        return AlbumPlanningPhoto(
            id: id, eventId: eventId,
            creationDate: Calendar.current.date(byAdding: .hour, value: hourOffset, to: base),
            pixelWidth: 1600, pixelHeight: 1200, coordinate: nil, place: nil,
            isFavorite: false, isEdited: false, burstIdentifier: nil, originalFilename: nil, exif: nil
        )
    }

    private func group(id: String, eventIds: [String], photoCount: Int) -> AlbumPhotoGroup {
        AlbumPhotoGroup(
            id: id, eventIds: eventIds,
            photos: (0..<photoCount).map { photo(id: "\(id)-\($0)", eventId: eventIds[0], hourOffset: $0) }
        )
    }

    // MARK: - § 30.3 Spread building

    @Test func twoPhotosMakeOneSpread() {
        let spreads = DefaultAlbumSpreadBuilder().buildSpreads(from: [group(id: "g", eventIds: ["e"], photoCount: 2)])
        #expect(spreads.count == 1)
        #expect(spreads[0].photos.count == 2)
    }

    @Test func sixPhotosMakeOneSpread() {
        let spreads = DefaultAlbumSpreadBuilder().buildSpreads(from: [group(id: "g", eventIds: ["e"], photoCount: 6)])
        #expect(spreads.count == 1)
        #expect(spreads[0].photos.count == 6)
    }

    @Test func sevenPhotosMakeTwoValidSpreads() {
        let spreads = DefaultAlbumSpreadBuilder().buildSpreads(from: [group(id: "g", eventIds: ["e"], photoCount: 7)])
        #expect(spreads.count == 2)
        for spread in spreads {
            #expect((2...6).contains(spread.photos.count))
        }
        #expect(spreads.reduce(0) { $0 + $1.photos.count } == 7)
    }

    @Test func thirteenPhotosNeverProduceASingletonSpread() {
        let spreads = DefaultAlbumSpreadBuilder().buildSpreads(from: [group(id: "g", eventIds: ["e"], photoCount: 13)])
        for spread in spreads {
            #expect((2...6).contains(spread.photos.count), "spread had \(spread.photos.count) photos")
        }
        #expect(spreads.reduce(0) { $0 + $1.photos.count } == 13)
    }

    @Test func everySpreadSizeIsWithinBounds() {
        for count in 2...40 {
            let spreads = DefaultAlbumSpreadBuilder().buildSpreads(from: [group(id: "g", eventIds: ["e"], photoCount: count)])
            for spread in spreads {
                #expect((2...6).contains(spread.photos.count), "photoCount=\(count) produced a spread of \(spread.photos.count)")
            }
            #expect(spreads.reduce(0) { $0 + $1.photos.count } == count, "photoCount=\(count) lost or duplicated photos")
        }
    }

    @Test func timelineOrderIsPreservedAcrossSpreads() {
        let spreads = DefaultAlbumSpreadBuilder().buildSpreads(from: [group(id: "g", eventIds: ["e"], photoCount: 8)])
        let flattenedIDs = spreads.flatMap { $0.photos.map(\.id) }
        let expectedIDs = (0..<8).map { "g-\($0)" }
        #expect(flattenedIDs == expectedIDs)
    }

    // MARK: - § 14.1 distribution examples from the spec

    @Test func distributionMatchesSpecExamples() {
        #expect(DefaultAlbumSpreadBuilder.distributeSpreadSizes(photoCount: 7) == [4, 3])
        #expect(DefaultAlbumSpreadBuilder.distributeSpreadSizes(photoCount: 9) == [5, 4])
        #expect(DefaultAlbumSpreadBuilder.distributeSpreadSizes(photoCount: 10) == [5, 5])
        #expect(DefaultAlbumSpreadBuilder.distributeSpreadSizes(photoCount: 11) == [6, 5])
        #expect(DefaultAlbumSpreadBuilder.distributeSpreadSizes(photoCount: 12) == [6, 6])
        #expect(DefaultAlbumSpreadBuilder.distributeSpreadSizes(photoCount: 13) == [5, 4, 4])
        #expect(DefaultAlbumSpreadBuilder.distributeSpreadSizes(photoCount: 15) == [5, 5, 5])
        #expect(DefaultAlbumSpreadBuilder.distributeSpreadSizes(photoCount: 17) == [6, 6, 5])
    }

    // MARK: - § 30.4 Event grouping (via AlbumPhotoGrouper, exercised together with the builder)

    @Test func smallEventStaysInOneSpread() {
        let grouper = DefaultAlbumPhotoGrouper()
        let event = AlbumPlanningEvent(
            id: "e1", title: nil, startDate: nil, endDate: nil, locationName: nil, latitude: nil, longitude: nil,
            selectedPhotos: (0..<4).map { photo(id: "p\($0)", eventId: "e1", hourOffset: $0) }
        )
        let groups = grouper.groupPhotos(from: [event])
        #expect(groups.count == 1)
        #expect(groups[0].photos.count == 4)

        let spreads = DefaultAlbumSpreadBuilder().buildSpreads(from: groups)
        #expect(spreads.count == 1)
    }

    @Test func largeEventSplitsIntoConsecutiveSpreads() {
        let grouper = DefaultAlbumPhotoGrouper()
        let event = AlbumPlanningEvent(
            id: "e1", title: nil, startDate: nil, endDate: nil, locationName: nil, latitude: nil, longitude: nil,
            selectedPhotos: (0..<14).map { photo(id: "p\($0)", eventId: "e1", hourOffset: $0) }
        )
        let groups = grouper.groupPhotos(from: [event])
        let spreads = DefaultAlbumSpreadBuilder().buildSpreads(from: groups)
        #expect(spreads.count > 1)
        #expect(spreads.allSatisfy { $0.sourceEventIds == ["e1"] })
        #expect(spreads.reduce(0) { $0 + $1.photos.count } == 14)
    }

    @Test func singlePhotoEventIsMergedWithNeighbor() {
        let grouper = DefaultAlbumPhotoGrouper()
        let eventA = AlbumPlanningEvent(
            id: "a", title: nil, startDate: DateComponents(calendar: .current, year: 2026, month: 1, day: 1).date,
            endDate: nil, locationName: nil, latitude: nil, longitude: nil,
            selectedPhotos: [photo(id: "a0", eventId: "a", hourOffset: 0)]
        )
        let eventB = AlbumPlanningEvent(
            id: "b", title: nil, startDate: DateComponents(calendar: .current, year: 2026, month: 1, day: 2).date,
            endDate: nil, locationName: nil, latitude: nil, longitude: nil,
            selectedPhotos: (0..<3).map { photo(id: "b\($0)", eventId: "b", hourOffset: 24 + $0) }
        )
        let groups = grouper.groupPhotos(from: [eventA, eventB])
        // The singleton must not survive as its own group.
        #expect(groups.allSatisfy { $0.photos.count != 1 })
        #expect(groups.reduce(0) { $0 + $1.photos.count } == 4)

        let spreads = DefaultAlbumSpreadBuilder().buildSpreads(from: groups)
        #expect(spreads.allSatisfy { (2...6).contains($0.photos.count) })
    }

    @Test func noPhotosAreLostOrDuplicatedAcrossGroupingAndMerging() {
        let grouper = DefaultAlbumPhotoGrouper()
        let events = (0..<5).map { eventIndex in
            AlbumPlanningEvent(
                id: "e\(eventIndex)", title: nil,
                startDate: Calendar.current.date(byAdding: .day, value: eventIndex, to: DateComponents(calendar: .current, year: 2026, month: 1, day: 1).date!),
                endDate: nil, locationName: nil, latitude: nil, longitude: nil,
                selectedPhotos: eventIndex == 2
                    ? [photo(id: "e2-only", eventId: "e2", hourOffset: 0)] // one singleton event
                    : (0..<3).map { photo(id: "e\(eventIndex)-\($0)", eventId: "e\(eventIndex)", hourOffset: $0) }
            )
        }
        let groups = grouper.groupPhotos(from: events)
        let allIDs = groups.flatMap { $0.photos.map(\.id) }
        let expectedIDs = events.flatMap { $0.selectedPhotos.map(\.id) }
        #expect(Set(allIDs) == Set(expectedIDs))
        #expect(allIDs.count == expectedIDs.count) // no duplicates
    }

    // MARK: - § 30.5 Partitions

    @Test func partitionsMatchSpecExactly() {
        #expect(validPartitions(totalPhotoCount: 2) == [.init(leftCount: 1, rightCount: 1)])
        #expect(validPartitions(totalPhotoCount: 3) == [.init(leftCount: 1, rightCount: 2), .init(leftCount: 2, rightCount: 1)])
        #expect(validPartitions(totalPhotoCount: 4) == [
            .init(leftCount: 1, rightCount: 3), .init(leftCount: 2, rightCount: 2), .init(leftCount: 3, rightCount: 1)
        ])
        #expect(validPartitions(totalPhotoCount: 5) == [
            .init(leftCount: 1, rightCount: 4), .init(leftCount: 2, rightCount: 3),
            .init(leftCount: 3, rightCount: 2), .init(leftCount: 4, rightCount: 1)
        ])
        #expect(validPartitions(totalPhotoCount: 6) == [
            .init(leftCount: 2, rightCount: 4), .init(leftCount: 3, rightCount: 3), .init(leftCount: 4, rightCount: 2)
        ])
    }

    @Test func noPartitionHasAPageOverFourPhotos() {
        for total in 2...6 {
            for partition in validPartitions(totalPhotoCount: total) {
                #expect(partition.leftCount <= 4 && partition.rightCount <= 4)
            }
        }
    }
}
