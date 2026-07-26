//
//  AlbumDraftPreviewFactory.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Preview/Diagnostics only — see docs/specs/SPEC-MODIFY-DRAFT.md § 3. `AlbumDraftPlanner`
/// itself never uses randomness (§ 2); this factory is what generates *varied mock input* for
/// the planner to run against, so the same deterministic planning algorithm produces a visibly
/// different-looking Album each time it's fed different mock data.
struct AlbumDraftPreviewConfiguration {
    let spreadCount: Int
    let minimumPhotosPerSpread: Int
    let maximumPhotosPerSpread: Int
    let seed: UInt64?

    static let varied = AlbumDraftPreviewConfiguration(
        spreadCount: 8, minimumPhotosPerSpread: 2, maximumPhotosPerSpread: 6, seed: nil
    )
}

protocol AlbumDraftPreviewBuilding {
    func makeInput(configuration: AlbumDraftPreviewConfiguration) -> AlbumPlanningInput
}

struct AlbumDraftPreviewFactory: AlbumDraftPreviewBuilding {
    /// § 5 — each mock Event already has 2–6 photos, so `AlbumPhotoGrouper`/`AlbumSpreadBuilder`
    /// keep every Event as its own Spread rather than the Planner re-splitting a single giant
    /// pile of photos into its own (more balanced, less visually varied) grouping.
    func makeInput(configuration: AlbumDraftPreviewConfiguration) -> AlbumPlanningInput {
        var generator = SeededRandomNumberGenerator(seed: configuration.seed ?? UInt64.random(in: .min ... .max))
        let counts = Self.makeSpreadPhotoCounts(count: configuration.spreadCount, using: &generator)

        let events: [AlbumPlanningEvent] = counts.enumerated().map { eventIndex, photoCount in
            let pattern = Self.orientationPattern(for: photoCount, using: &generator)
            let photos = pattern.enumerated().map { photoIndex, orientation -> AlbumPlanningPhoto in
                let (width, height) = Self.dimensions(for: orientation, index: photoIndex)
                return AlbumPlanningPhoto(
                    id: "preview-\(eventIndex)-\(photoIndex)",
                    eventId: "preview-event-\(eventIndex)",
                    creationDate: Calendar.current.date(byAdding: .hour, value: photoIndex, to: Self.baseDate(eventIndex: eventIndex)),
                    pixelWidth: width, pixelHeight: height,
                    coordinate: nil, place: nil,
                    isFavorite: Int.random(in: 0..<8, using: &generator) == 0,
                    isEdited: Int.random(in: 0..<6, using: &generator) == 0,
                    burstIdentifier: nil, originalFilename: nil, exif: nil
                )
            }
            return AlbumPlanningEvent(
                id: "preview-event-\(eventIndex)", title: Self.eventTitle(index: eventIndex),
                startDate: Self.baseDate(eventIndex: eventIndex), endDate: Self.baseDate(eventIndex: eventIndex),
                locationName: nil, latitude: nil, longitude: nil, selectedPhotos: photos
            )
        }

        return AlbumPlanningInput(albumTitle: nil, events: events)
    }

    // MARK: - § 4 Spread photo counts — bag of 2...6, reshuffled on empty, never repeating the
    // immediately-previous value when a different choice is available.

    private static func makeSpreadPhotoCounts<G: RandomNumberGenerator>(count: Int, using generator: inout G) -> [Int] {
        var result: [Int] = []
        var bag = [2, 3, 4, 5, 6]

        while result.count < count {
            bag.shuffle(using: &generator)
            for value in bag {
                guard result.count < count else { break }
                if result.last == value { continue }
                result.append(value)
            }
        }
        return result
    }

    // MARK: - § 6 Orientation patterns

    private static let orientationPatterns: [Int: [[PhotoOrientation]]] = [
        2: [[.landscape, .portrait], [.square, .landscape], [.portrait, .portrait]],
        3: [[.landscape, .portrait, .square], [.portrait, .portrait, .landscape], [.landscape, .landscape, .square]],
        4: [
            [.landscape, .landscape, .portrait, .square],
            [.portrait, .portrait, .landscape, .square],
            [.landscape, .portrait, .portrait, .landscape]
        ],
        5: [
            [.landscape, .landscape, .portrait, .portrait, .square],
            [.portrait, .portrait, .portrait, .landscape, .square],
            [.landscape, .landscape, .landscape, .portrait, .portrait]
        ],
        6: [
            [.landscape, .landscape, .portrait, .portrait, .portrait, .square],
            [.landscape, .landscape, .landscape, .portrait, .portrait, .square],
            [.portrait, .portrait, .portrait, .landscape, .landscape, .square]
        ]
    ]

    private static func orientationPattern<G: RandomNumberGenerator>(for count: Int, using generator: inout G) -> [PhotoOrientation] {
        guard let patterns = orientationPatterns[count], !patterns.isEmpty else {
            return Array(repeating: .square, count: count)
        }
        return patterns.randomElement(using: &generator) ?? patterns[0]
    }

    // MARK: - § 7 Dimensions — real, orientation-consistent pixel sizes, not a fixed stand-in.

    private static func dimensions(for orientation: PhotoOrientation, index: Int) -> (width: Int, height: Int) {
        switch orientation {
        case .landscape: return index.isMultiple(of: 2) ? (4032, 3024) : (3840, 2160)
        case .portrait: return index.isMultiple(of: 2) ? (3024, 4032) : (2160, 3840)
        case .square: return (3024, 3024)
        }
    }

    private static func baseDate(eventIndex: Int) -> Date {
        let start = DateComponents(calendar: .current, year: 2026, month: 1, day: 1).date!
        return Calendar.current.date(byAdding: .day, value: eventIndex, to: start) ?? start
    }

    private static let eventTitles = [
        "Morning Walk", "City Lights", "Weekend Getaway", "Family Time", "Coffee Run",
        "Sunset Drive", "Garden Visit", "Old Town", "Lake Trip", "Market Day",
        "Rooftop Views", "Rainy Afternoon"
    ]

    private static func eventTitle(index: Int) -> String {
        eventTitles[index % eventTitles.count]
    }
}
