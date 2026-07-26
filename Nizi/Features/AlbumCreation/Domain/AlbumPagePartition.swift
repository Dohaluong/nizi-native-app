//
//  AlbumPagePartition.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// One way to split a Spread's photos between its left and right page.
struct AlbumPagePartition: Hashable {
    let leftCount: Int
    let rightCount: Int
}

/// Every valid `(left, right)` split of `totalPhotoCount` — both sides `1...4` (the layout
/// library's supported photo counts per page), sorted by ascending `leftCount` to match the
/// exact ordering in the spec. See docs/specs/SPEC-ALBUM-DRAFT-PLANNER.md § 15:
///
/// ```text
/// 2 → 1+1
/// 3 → 1+2, 2+1
/// 4 → 1+3, 2+2, 3+1
/// 5 → 1+4, 2+3, 3+2, 4+1
/// 6 → 2+4, 3+3, 4+2
/// ```
func validPartitions(totalPhotoCount: Int) -> [AlbumPagePartition] {
    guard (2...6).contains(totalPhotoCount) else { return [] }
    return (1...4)
        .compactMap { left -> AlbumPagePartition? in
            let right = totalPhotoCount - left
            guard (1...4).contains(right) else { return nil }
            return AlbumPagePartition(leftCount: left, rightCount: right)
        }
        .sorted { $0.leftCount < $1.leftCount }
}
