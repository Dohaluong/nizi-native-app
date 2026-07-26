//
//  AdjustParameterTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import Testing
@testable import Nizi

struct AdjustParameterTests {
    @Test
    func everyParameterReadsItsOwnFieldOnly() {
        var adjustments = PhotoAdjustments()
        adjustments.exposure = 0.1
        adjustments.contrast = 0.2
        adjustments.highlights = 0.3
        adjustments.shadows = 0.4
        adjustments.warmth = 0.5
        adjustments.saturation = 0.6

        #expect(AdjustParameter.exposure.value(in: adjustments) == 0.1)
        #expect(AdjustParameter.contrast.value(in: adjustments) == 0.2)
        #expect(AdjustParameter.highlights.value(in: adjustments) == 0.3)
        #expect(AdjustParameter.shadows.value(in: adjustments) == 0.4)
        #expect(AdjustParameter.warmth.value(in: adjustments) == 0.5)
        #expect(AdjustParameter.saturation.value(in: adjustments) == 0.6)
    }

    @Test
    func settingOneParameterNeverTouchesTheOthers() {
        for parameter in AdjustParameter.allCases {
            var adjustments = PhotoAdjustments()
            parameter.setting(0.42, in: &adjustments)

            #expect(parameter.value(in: adjustments) == 0.42)
            for other in AdjustParameter.allCases where other != parameter {
                #expect(other.value(in: adjustments) == 0, "\(other) was touched by setting \(parameter)")
            }
        }
    }

    @Test
    func allCasesAreExactlyTheSixSpecifiedParameters() {
        let ids = Set(AdjustParameter.allCases.map(\.id))
        #expect(ids == ["exposure", "contrast", "highlights", "shadows", "warmth", "saturation"])
    }
}
