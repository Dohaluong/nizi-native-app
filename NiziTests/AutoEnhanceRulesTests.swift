//
//  AutoEnhanceRulesTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import Testing
@testable import Nizi

struct AutoEnhanceRulesTests {
    private func neutralStats(
        averageBrightness: Float = 0.45,
        shadowClippingRatio: Float = 0,
        highlightClippingRatio: Float = 0,
        averageSaturation: Float = 0.4
    ) -> PhotoHistogramStatistics {
        PhotoHistogramStatistics(
            averageBrightness: averageBrightness,
            shadowClippingRatio: shadowClippingRatio,
            highlightClippingRatio: highlightClippingRatio,
            averageSaturation: averageSaturation
        )
    }

    @Test
    func wellExposedPhotoSuggestsNoChange() {
        let adjustments = AutoEnhanceRules.suggestedAdjustments(for: neutralStats())
        #expect(adjustments.isIdentity)
    }

    @Test
    func darkPhotoSuggestsPositiveExposure() {
        let stats = neutralStats(averageBrightness: 0.2)
        let adjustments = AutoEnhanceRules.suggestedAdjustments(for: stats)
        #expect(adjustments.exposure > 0)
    }

    @Test
    func brightPhotoSuggestsNegativeExposure() {
        let stats = neutralStats(averageBrightness: 0.75)
        let adjustments = AutoEnhanceRules.suggestedAdjustments(for: stats)
        #expect(adjustments.exposure < 0)
    }

    @Test
    func exposureSuggestionIsAlwaysClampedToAModestRange() {
        // Deliberately extreme input — the suggestion must never read as a drastic edit.
        let veryDark = neutralStats(averageBrightness: 0.0)
        let veryBright = neutralStats(averageBrightness: 1.0)
        #expect(AutoEnhanceRules.suggestedAdjustments(for: veryDark).exposure <= 0.35)
        #expect(AutoEnhanceRules.suggestedAdjustments(for: veryBright).exposure >= -0.35)
    }

    @Test
    func highHighlightClippingSuggestsRecoveringHighlights() {
        let stats = neutralStats(highlightClippingRatio: 0.2)
        let adjustments = AutoEnhanceRules.suggestedAdjustments(for: stats)
        #expect(adjustments.highlights < 0)
    }

    @Test
    func highShadowClippingSuggestsLiftingShadows() {
        let stats = neutralStats(shadowClippingRatio: 0.2)
        let adjustments = AutoEnhanceRules.suggestedAdjustments(for: stats)
        #expect(adjustments.shadows > 0)
    }

    @Test
    func lowSaturationSuggestsAModestSaturationBoost() {
        let stats = neutralStats(averageSaturation: 0.05)
        let adjustments = AutoEnhanceRules.suggestedAdjustments(for: stats)
        #expect(adjustments.saturation > 0)
    }

    @Test
    func neverSuggestsWarmthChanges() {
        // Warmth isn't derived from any of the measured statistics — this pins that down so a
        // future change to the rules can't silently start suggesting it without a deliberate,
        // reviewed decision (§ 9.1 lists "cân bằng màu cơ bản" but this app's V1 heuristics don't
        // attempt white-balance correction).
        for stats in [
            neutralStats(averageBrightness: 0.1),
            neutralStats(averageBrightness: 0.9),
            neutralStats(shadowClippingRatio: 0.3),
            neutralStats(highlightClippingRatio: 0.3),
            neutralStats(averageSaturation: 0.02)
        ] {
            #expect(AutoEnhanceRules.suggestedAdjustments(for: stats).warmth == 0)
        }
    }
}
