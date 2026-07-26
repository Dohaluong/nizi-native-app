//
//  PhotoImportanceEvaluator.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Scores every photo once, up front — the Cover Selector, hero slot assignment, and layout-pair
/// scoring all read `photo.importance.totalScore` afterward rather than recomputing similar
/// criteria themselves (§ 6.1, § 6.4: "Không tính scoring lần thứ hai trong Cover Selector").
protocol PhotoImportanceEvaluating: Sendable {
    func evaluate(photos: [AlbumPlanningPhoto]) -> [String: PhotoImportance]
}

struct DefaultPhotoImportanceEvaluator: PhotoImportanceEvaluating {
    func evaluate(photos: [AlbumPlanningPhoto]) -> [String: PhotoImportance] {
        guard !photos.isEmpty else { return [:] }

        let maxPixelCount = photos.map(\.pixelCount).max() ?? 0
        let dates = photos.compactMap(\.creationDate).sorted()
        let earliest = dates.first
        let latest = dates.last

        var result: [String: PhotoImportance] = [:]
        for photo in photos {
            var reasons: [PhotoImportanceReason] = []

            if photo.isFavorite { reasons.append(.favorite(30)) }

            if maxPixelCount > 0 {
                let resolutionScore = 25 * (Double(photo.pixelCount) / Double(maxPixelCount))
                if resolutionScore > 0 { reasons.append(.resolution(resolutionScore)) }
            }

            if photo.isEdited { reasons.append(.edited(5)) }

            // § 6.3 — only scored when there's enough timeline data; otherwise 0, never a penalty.
            if let date = photo.creationDate, let earliest, let latest, latest > earliest {
                let position = date.timeIntervalSince(earliest) / latest.timeIntervalSince(earliest)
                if (0.20...0.80).contains(position) {
                    reasons.append(.timelinePosition(10))
                }
            }

            switch photo.orientation {
            case .landscape: reasons.append(.orientation(15))
            case .square: reasons.append(.orientation(12))
            case .portrait: reasons.append(.orientation(8))
            case nil: break
            }

            if photo.place != nil { reasons.append(.hasLocation(3)) }

            let totalScore = reasons.reduce(0) { $0 + $1.score }
            result[photo.id] = PhotoImportance(totalScore: totalScore, reasons: reasons)
        }
        return result
    }
}
