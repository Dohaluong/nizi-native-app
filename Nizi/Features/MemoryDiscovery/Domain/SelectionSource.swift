//
//  SelectionSource.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// See docs/sprint/SPRINT-005B.md § 17. The user's choice always wins over the algorithm's —
/// `userAdded`/`userRemoved` items are never reverted by a cache-valid reopen (only an explicit
/// re-curation, which is itself a user-initiated action, can replace them).
enum SelectionSource: String, Equatable {
    case systemSuggested
    case userAdded
    case userRemoved
}
