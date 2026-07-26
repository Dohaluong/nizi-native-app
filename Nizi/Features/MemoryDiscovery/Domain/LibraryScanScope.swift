//
//  LibraryScanScope.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// What part of the library the user chose to survey — see docs/sprint/SPRINT-005-UI.md § 4
/// (Scope Selection). Not persisted across app relaunches mid-scan: if a scoped scan is paused
/// and the app is killed before resuming, resuming picks the scope passed to that call again
/// (normally still held by the screen that started it). See
/// docs/sprint/SPRINT-005-INTEGRATION-CHECKLIST.md for that tradeoff.
enum LibraryScanScope: Equatable {
    case fullLibrary
    case years(Set<Int>)
    case yearMonths(year: Int, months: Set<Int>)

    /// How many years back the static year picker offers — no PhotoKit access yet at this
    /// point in the flow (permission comes after scope selection), so this can't be derived
    /// from the actual library. SPEC's own example list runs a similar span.
    static func selectableYears(currentYear: Int = Calendar.current.component(.year, from: Date())) -> [Int] {
        Array((currentYear - 16)...currentYear).reversed()
    }

    func dateRanges(calendar: Calendar = .current, now: Date = Date()) -> [DateRangeFilter] {
        switch self {
        case .fullLibrary:
            return []

        case .years(let years):
            return years.compactMap { year in
                Self.yearRange(year, calendar: calendar)
            }

        case .yearMonths(let year, let months):
            return months.compactMap { month in
                Self.monthRange(year: year, month: month, calendar: calendar)
            }
        }
    }

    private static func yearRange(_ year: Int, calendar: Calendar) -> DateRangeFilter? {
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let nextYearStart = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
        else {
            return nil
        }
        return DateRangeFilter(start: start, end: nextYearStart.addingTimeInterval(-1))
    }

    private static func monthRange(year: Int, month: Int, calendar: Calendar) -> DateRangeFilter? {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start)
        else {
            return nil
        }
        return DateRangeFilter(start: start, end: end)
    }
}
