//
//  DateRangeFilter.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// A closed date interval used to scope a PhotoKit fetch to part of the library.
/// An empty `[DateRangeFilter]` array means "no filter — the whole library".
struct DateRangeFilter: Equatable {
    let start: Date
    let end: Date
}
