//
//  AlbumPhotoGrouper.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Sorts and groups photos by Event, in preparation for `AlbumSpreadBuilder`. See
/// docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 12–13.
protocol AlbumPhotoGrouping {
    func groupPhotos(from events: [AlbumPlanningEvent]) -> [AlbumPhotoGroup]
}

struct DefaultAlbumPhotoGrouper: AlbumPhotoGrouping {
    func groupPhotos(from events: [AlbumPlanningEvent]) -> [AlbumPhotoGroup] {
        // § 12: events by startDate, photos within an event by creationDate — undated last,
        // photo ID as the final deterministic tie breaker throughout.
        let sortedEvents = events.sorted(by: Self.eventOrder)

        var groups: [AlbumPhotoGroup] = sortedEvents.compactMap { event in
            guard !event.selectedPhotos.isEmpty else { return nil }
            return AlbumPhotoGroup(
                id: "group-\(event.id)",
                eventIds: [event.id],
                photos: event.selectedPhotos.sorted(by: Self.photoOrder)
            )
        }

        return mergeSingletonGroups(groups: &groups)
    }

    private static func eventOrder(_ lhs: AlbumPlanningEvent, _ rhs: AlbumPlanningEvent) -> Bool {
        switch (lhs.startDate, rhs.startDate) {
        case let (l?, r?) where l != r: return l < r
        case (nil, .some): return false
        case (.some, nil): return true
        default: return lhs.id < rhs.id
        }
    }

    private static func photoOrder(_ lhs: AlbumPlanningPhoto, _ rhs: AlbumPlanningPhoto) -> Bool {
        switch (lhs.creationDate, rhs.creationDate) {
        case let (l?, r?) where l != r: return l < r
        case (nil, .some): return false
        case (.some, nil): return true
        default: return lhs.id < rhs.id
        }
    }

    /// § 13.3 — a 1-photo group can never form a Spread (minimum 2 photos) on its own. Merge it
    /// into the previous timeline-adjacent group if that stays within the 6-photo Spread cap,
    /// otherwise the next one. If it's the *only* group, it's left as-is — the planner's input
    /// validation step (`AlbumPlanningValidator`) rejects a total selection under 2 photos before
    /// this is ever reached, so that case shouldn't occur with valid input.
    private func mergeSingletonGroups(groups: inout [AlbumPhotoGroup]) -> [AlbumPhotoGroup] {
        guard groups.count > 1 else { return groups }

        var index = 0
        while index < groups.count {
            guard groups[index].photos.count == 1 else {
                index += 1
                continue
            }
            if index > 0, groups[index - 1].photos.count + 1 <= 6 {
                groups[index - 1] = merged(groups[index - 1], groups[index])
                groups.remove(at: index)
            } else if index < groups.count - 1 {
                groups[index + 1] = merged(groups[index], groups[index + 1])
                groups.remove(at: index)
            } else {
                index += 1
            }
        }
        return groups
    }

    private func merged(_ a: AlbumPhotoGroup, _ b: AlbumPhotoGroup) -> AlbumPhotoGroup {
        AlbumPhotoGroup(
            id: "\(a.id)+\(b.id)",
            eventIds: a.eventIds + b.eventIds,
            photos: (a.photos + b.photos).sorted(by: Self.photoOrder)
        )
    }
}
