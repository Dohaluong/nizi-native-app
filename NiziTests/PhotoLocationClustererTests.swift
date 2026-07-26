//
//  PhotoLocationClustererTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

struct PhotoLocationClustererTests {
    private func photo(id: String, coordinate: PhotoCoordinate?, hourOffset: Int = 0) -> AlbumPlanningPhoto {
        let base = DateComponents(calendar: .current, year: 2026, month: 1, day: 1).date!
        return AlbumPlanningPhoto(
            id: id, eventId: "e", creationDate: Calendar.current.date(byAdding: .hour, value: hourOffset, to: base),
            pixelWidth: 1600, pixelHeight: 1200, coordinate: coordinate, place: nil,
            isFavorite: false, isEdited: false, burstIdentifier: nil, originalFilename: nil, exif: nil
        )
    }

    // Sydney Opera House-ish coordinates, ~30m apart.
    private let coordinateA = PhotoCoordinate(latitude: -33.8568, longitude: 151.2153)!
    private let coordinateAVeryClose = PhotoCoordinate(latitude: -33.8570, longitude: 151.2154)!
    // Somewhere in Hanoi — far away.
    private let coordinateB = PhotoCoordinate(latitude: 21.0278, longitude: 105.8342)!

    @Test func photosWithinDistanceShareACluster() {
        let photos = [photo(id: "a1", coordinate: coordinateA), photo(id: "a2", coordinate: coordinateAVeryClose, hourOffset: 1)]
        let clusters = DefaultPhotoLocationClusterer().clusters(from: photos, maximumDistance: 100)
        #expect(clusters.count == 1)
        #expect(Set(clusters[0].photoIds) == ["a1", "a2"])
    }

    @Test func farApartPhotosGetDifferentClusters() {
        let photos = [photo(id: "a1", coordinate: coordinateA), photo(id: "b1", coordinate: coordinateB, hourOffset: 1)]
        let clusters = DefaultPhotoLocationClusterer().clusters(from: photos, maximumDistance: 100)
        #expect(clusters.count == 2)
    }

    @Test func photosWithoutCoordinateAreIgnored() {
        let photos = [photo(id: "a1", coordinate: coordinateA), photo(id: "none", coordinate: nil)]
        let clusters = DefaultPhotoLocationClusterer().clusters(from: photos, maximumDistance: 100)
        let allClusteredIDs = clusters.flatMap(\.photoIds)
        #expect(!allClusteredIDs.contains("none"))
        #expect(allClusteredIDs.contains("a1"))
    }

    @Test func everyPhotoIDAppearsAtMostOnce() {
        let photos = [
            photo(id: "a1", coordinate: coordinateA), photo(id: "a2", coordinate: coordinateAVeryClose, hourOffset: 1),
            photo(id: "b1", coordinate: coordinateB, hourOffset: 2)
        ]
        let clusters = DefaultPhotoLocationClusterer().clusters(from: photos, maximumDistance: 100)
        let allIDs = clusters.flatMap(\.photoIds)
        #expect(Set(allIDs).count == allIDs.count)
    }

    @Test func resultIsDeterministic() {
        let photos = [
            photo(id: "a1", coordinate: coordinateA), photo(id: "b1", coordinate: coordinateB, hourOffset: 1),
            photo(id: "a2", coordinate: coordinateAVeryClose, hourOffset: 2)
        ]
        let clusterer = DefaultPhotoLocationClusterer()
        let first = clusterer.clusters(from: photos, maximumDistance: 100)
        let second = clusterer.clusters(from: photos, maximumDistance: 100)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.photoIds) == second.map(\.photoIds))
    }
}
