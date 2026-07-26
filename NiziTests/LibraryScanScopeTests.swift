//
//  LibraryScanScopeTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation
import Testing
@testable import Nizi

struct LibraryScanScopeTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func fullLibraryHasNoDateRanges() {
        #expect(LibraryScanScope.fullLibrary.dateRanges(calendar: calendar).isEmpty)
    }

    @Test func singleYearProducesJanuaryFirstToDecemberThirtyFirst() throws {
        let ranges = LibraryScanScope.years([2024]).dateRanges(calendar: calendar)
        let range = try #require(ranges.first)

        let startComponents = calendar.dateComponents([.year, .month, .day], from: range.start)
        #expect(startComponents.year == 2024 && startComponents.month == 1 && startComponents.day == 1)

        let endComponents = calendar.dateComponents([.year, .month, .day], from: range.end)
        #expect(endComponents.year == 2024 && endComponents.month == 12 && endComponents.day == 31)
    }

    @Test func multipleYearsProduceOneRangeEach() {
        let ranges = LibraryScanScope.years([2022, 2024]).dateRanges(calendar: calendar)
        #expect(ranges.count == 2)
    }

    @Test func monthRangeStaysWithinTheSelectedMonth() throws {
        let ranges = LibraryScanScope.yearMonths(year: 2024, months: [2]).dateRanges(calendar: calendar)
        let range = try #require(ranges.first)

        let startComponents = calendar.dateComponents([.year, .month, .day], from: range.start)
        #expect(startComponents.year == 2024 && startComponents.month == 2 && startComponents.day == 1)

        // 2024 is a leap year — February has 29 days.
        let endComponents = calendar.dateComponents([.year, .month, .day], from: range.end)
        #expect(endComponents.year == 2024 && endComponents.month == 2 && endComponents.day == 29)
    }

    @Test func selectableYearsEndsAtCurrentYearAndIsDescending() {
        let years = LibraryScanScope.selectableYears(currentYear: 2026)
        #expect(years.first == 2026)
        #expect(years == years.sorted(by: >))
        #expect(years.last == 2010)
    }
}
