//
//  PhotoImportanceEvaluatorTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation
import Testing
@testable import Nizi

struct PhotoImportanceEvaluatorTests {
    private func photo(
        id: String, width: Int = 1600, height: Int = 1200, creationDate: Date? = nil,
        isFavorite: Bool = false, isEdited: Bool = false, place: PhotoPlace? = nil
    ) -> AlbumPlanningPhoto {
        AlbumPlanningPhoto(
            id: id, eventId: "e", creationDate: creationDate, pixelWidth: width, pixelHeight: height,
            coordinate: nil, place: place, isFavorite: isFavorite, isEdited: isEdited,
            burstIdentifier: nil, originalFilename: nil, exif: nil
        )
    }

    @Test func favoriteAddsThirtyPoints() {
        let favorite = photo(id: "fav", width: 100, height: 100, isFavorite: true)
        let plain = photo(id: "plain", width: 100, height: 100, isFavorite: false)
        let result = DefaultPhotoImportanceEvaluator().evaluate(photos: [favorite, plain])
        #expect(result["fav"]!.totalScore - result["plain"]!.totalScore == 30)
    }

    @Test func resolutionNormalizesWithinTheSet() {
        let small = photo(id: "small", width: 400, height: 300) // pixelCount = 120,000
        let big = photo(id: "big", width: 1600, height: 1200) // pixelCount = 1,920,000 (max)
        let result = DefaultPhotoImportanceEvaluator().evaluate(photos: [small, big])
        #expect(result["big"]!.totalScore == 25) // exactly the max score, no other bonuses
        #expect(abs(result["small"]!.totalScore - 25 * (120_000.0 / 1_920_000.0)) < 0.01)
    }

    @Test func orientationScoresAreCorrect() {
        let landscape = photo(id: "l", width: 1600, height: 1200)
        let portrait = photo(id: "p", width: 1200, height: 1600)
        let square = photo(id: "s", width: 1000, height: 1000)
        let result = DefaultPhotoImportanceEvaluator().evaluate(photos: [landscape, portrait, square])
        // All three have equal resolution contribution in this trio (different pixel counts
        // actually — isolate orientation by checking presence of the specific reason code/value).
        #expect(result["l"]!.reasons.first { $0.code == "orientation" }?.score == 15)
        #expect(result["s"]!.reasons.first { $0.code == "orientation" }?.score == 12)
        #expect(result["p"]!.reasons.first { $0.code == "orientation" }?.score == 8)
    }

    @Test func timelineMiddleGetsBonus() {
        let early = Date(timeIntervalSince1970: 0)
        let middle = Date(timeIntervalSince1970: 500)
        let late = Date(timeIntervalSince1970: 1000)
        let photos = [
            photo(id: "early", creationDate: early),
            photo(id: "middle", creationDate: middle),
            photo(id: "late", creationDate: late)
        ]
        let result = DefaultPhotoImportanceEvaluator().evaluate(photos: photos)
        #expect(result["middle"]!.reasons.contains { $0.code == "timelinePosition" })
        #expect(!result["early"]!.reasons.contains { $0.code == "timelinePosition" })
        #expect(!result["late"]!.reasons.contains { $0.code == "timelinePosition" })
    }

    @Test func hasLocationAddsThreePoints() {
        let place = PhotoPlace(coordinate: PhotoCoordinate(latitude: 0, longitude: 0)!, name: nil, subLocality: nil, locality: nil, subAdministrativeArea: nil, administrativeArea: nil, country: nil, isoCountryCode: nil, displayName: "")
        let withPlace = photo(id: "with", place: place)
        let withoutPlace = photo(id: "without", place: nil)
        let result = DefaultPhotoImportanceEvaluator().evaluate(photos: [withPlace, withoutPlace])
        #expect(result["with"]!.totalScore - result["without"]!.totalScore == 3)
    }

    @Test func missingDateDoesNotCrashOrPenalize() {
        let noDate = photo(id: "nodate", creationDate: nil)
        let result = DefaultPhotoImportanceEvaluator().evaluate(photos: [noDate])
        #expect(result["nodate"] != nil)
        #expect(!result["nodate"]!.reasons.contains { $0.code == "timelinePosition" })
    }

    @Test func resultIsDeterministicForTheSameInput() {
        let photos = [photo(id: "a", isFavorite: true), photo(id: "b", width: 800, height: 600)]
        let evaluator = DefaultPhotoImportanceEvaluator()
        let first = evaluator.evaluate(photos: photos)
        let second = evaluator.evaluate(photos: photos)
        #expect(first["a"]!.totalScore == second["a"]!.totalScore)
        #expect(first["b"]!.totalScore == second["b"]!.totalScore)
    }

    @Test func emptyInputReturnsEmptyResult() {
        #expect(DefaultPhotoImportanceEvaluator().evaluate(photos: []).isEmpty)
    }
}
