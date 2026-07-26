//
//  EventDateRangeFormatter.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Single, centralized entry point for formatting an event's start/end dates as one
/// locale-aware string — no manual date-component extraction, hardcoded separators, or
/// fixed day/month ordering anywhere else in the app. Event date ranges are shown in
/// multiple screens (and will be in more as the Event feature grows), so every call site
/// should route through here rather than composing its own `DateFormatter`/`dateFormat` string.
///
/// Not yet consumed by a view as of this pass: today's Presentation layer only shows a single
/// start date (`EventCardView`) or per-moment timestamps (`EventDetailView`'s group headers),
/// never a live two-date range independent of `PhotoEvent.titleSuggestion` (which is generated
/// in the Domain layer and intentionally left untouched — see docs/LOCALIZATION.md). This exists
/// as ready infrastructure for the next screen that needs one.
enum EventDateRangeFormatter {
    static func format(start: Date, end: Date, calendar: Calendar = .current) -> String {
        guard start <= end else {
            return format(start: end, end: start, calendar: calendar)
        }
        if calendar.isDate(start, inSameDayAs: end) {
            return start.formatted(date: .abbreviated, time: .omitted)
        }
        let style = Date.IntervalFormatStyle(date: .abbreviated, time: .omitted, calendar: calendar)
        return style.format(start..<end)
    }
}
