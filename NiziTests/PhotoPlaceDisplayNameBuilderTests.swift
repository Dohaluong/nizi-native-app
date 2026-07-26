//
//  PhotoPlaceDisplayNameBuilderTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/25/26.
//

import Testing
@testable import Nizi

struct PhotoPlaceDisplayNameBuilderTests {
    private let builder = PhotoPlaceDisplayNameBuilder()

    @Test func removesDuplicateComponents() {
        let name = builder.makeDisplayName(name: nil, subLocality: nil, locality: "Hà Nội", administrativeArea: "Hà Nội", country: "Việt Nam")
        #expect(name == "Hà Nội, Việt Nam")
    }

    @Test func noTrailingOrExtraCommas() {
        let name = builder.makeDisplayName(name: "Sydney Opera House", subLocality: nil, locality: "Sydney", administrativeArea: nil, country: nil)
        #expect(!name.hasSuffix(","))
        #expect(!name.contains(",,"))
    }

    @Test func keepsAtMostTwoComponents() {
        let name = builder.makeDisplayName(name: "Sydney Opera House", subLocality: "Circular Quay", locality: "Sydney", administrativeArea: "NSW", country: "Australia")
        #expect(name.components(separatedBy: ", ").count == 2)
        #expect(name == "Sydney Opera House, Circular Quay")
    }

    @Test func fallsBackWhenNameIsMissing() {
        let name = builder.makeDisplayName(name: nil, subLocality: nil, locality: "Sydney", administrativeArea: nil, country: "Australia")
        #expect(name == "Sydney, Australia")
    }

    @Test func supportsLocalityAndCountryOnly() {
        let name = builder.makeDisplayName(name: nil, subLocality: nil, locality: nil, administrativeArea: nil, country: "Australia")
        #expect(name == "Australia")
    }

    @Test func emptyWhenNothingResolved() {
        let name = builder.makeDisplayName(name: nil, subLocality: nil, locality: nil, administrativeArea: nil, country: nil)
        #expect(name.isEmpty)
    }

    @Test func trimsWhitespaceAndDropsEmptyStrings() {
        let name = builder.makeDisplayName(name: "  ", subLocality: nil, locality: " Sydney ", administrativeArea: nil, country: "Australia")
        #expect(name == "Sydney, Australia")
    }
}
