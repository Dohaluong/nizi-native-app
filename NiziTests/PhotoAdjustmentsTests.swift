//
//  PhotoAdjustmentsTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import Testing
@testable import Nizi

struct PhotoAdjustmentsTests {
    @Test
    func defaultsToIdentity() {
        let adjustments = PhotoAdjustments()
        #expect(adjustments == .identity)
        #expect(adjustments.isIdentity)
    }

    @Test
    func nonZeroFieldIsNotIdentity() {
        var adjustments = PhotoAdjustments()
        adjustments.exposure = 0.2
        #expect(!adjustments.isIdentity)
    }

    @Test
    func codableRoundTrip() throws {
        var adjustments = PhotoAdjustments()
        adjustments.exposure = 0.1
        adjustments.contrast = -0.2
        adjustments.highlights = 0.3
        adjustments.shadows = -0.4
        adjustments.warmth = 0.05
        adjustments.saturation = -0.15

        let data = try JSONEncoder().encode(adjustments)
        let decoded = try JSONDecoder().decode(PhotoAdjustments.self, from: data)
        #expect(decoded == adjustments)
    }
}
