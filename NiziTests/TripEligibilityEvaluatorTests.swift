//
//  TripEligibilityEvaluatorTests.swift
//  NiziTests
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation
import Testing
@testable import Nizi

struct TripEligibilityEvaluatorTests {
    private func makeCandidate(
        overnightCount: Int = 0,
        maxDistanceFromHomeKm: Double? = nil,
        totalSessionCount: Int = 1,
        durationHours: Double = 1
    ) -> TripCandidate {
        TripCandidate(
            events: [], overnightCount: overnightCount, maxDistanceFromHomeKm: maxDistanceFromHomeKm,
            totalSessionCount: totalSessionCount, durationHours: durationHours
        )
    }

    @Test func overnightAwayAndFarEnoughIsEligible() {
        let candidate = makeCandidate(overnightCount: 1, maxDistanceFromHomeKm: 30)
        let decision = DefaultTripEligibilityEvaluator().evaluate(candidate: candidate, config: .default)
        #expect(decision.isEligible)
        #expect(decision.reasons == [TripEligibilityReason.overnight.rawValue])
    }

    @Test func overnightButTooCloseIsNotEligible() {
        let candidate = makeCandidate(overnightCount: 1, maxDistanceFromHomeKm: 24)
        let decision = DefaultTripEligibilityEvaluator().evaluate(candidate: candidate, config: .default)
        #expect(!decision.isEligible)
    }

    @Test func dayTripNeedsDurationDistanceAndSessionsTogether() {
        let full = makeCandidate(overnightCount: 0, maxDistanceFromHomeKm: 30, totalSessionCount: 2, durationHours: 4)
        #expect(DefaultTripEligibilityEvaluator().evaluate(candidate: full, config: .default).isEligible)

        let tooFewSessions = makeCandidate(overnightCount: 0, maxDistanceFromHomeKm: 30, totalSessionCount: 1, durationHours: 4)
        #expect(!DefaultTripEligibilityEvaluator().evaluate(candidate: tooFewSessions, config: .default).isEligible)

        let tooShort = makeCandidate(overnightCount: 0, maxDistanceFromHomeKm: 30, totalSessionCount: 2, durationHours: 1)
        #expect(!DefaultTripEligibilityEvaluator().evaluate(candidate: tooShort, config: .default).isEligible)

        let tooClose = makeCandidate(overnightCount: 0, maxDistanceFromHomeKm: 10, totalSessionCount: 2, durationHours: 4)
        #expect(!DefaultTripEligibilityEvaluator().evaluate(candidate: tooClose, config: .default).isEligible)
    }

    @Test func farEnoughAloneIsInternationalCandidateEvenWithNoOtherSignal() {
        let candidate = makeCandidate(overnightCount: 0, maxDistanceFromHomeKm: 200, totalSessionCount: 1, durationHours: 0.5)
        let decision = DefaultTripEligibilityEvaluator().evaluate(candidate: candidate, config: .default)
        #expect(decision.isEligible)
        #expect(decision.reasons == [TripEligibilityReason.internationalCandidate.rawValue])
    }

    @Test func noSignalsAtAllIsNotEligible() {
        let candidate = makeCandidate(overnightCount: 0, maxDistanceFromHomeKm: 21, totalSessionCount: 1, durationHours: 0.25)
        let decision = DefaultTripEligibilityEvaluator().evaluate(candidate: candidate, config: .default)
        #expect(!decision.isEligible)
        #expect(decision.reasons.isEmpty)
    }

    @Test func nilDistanceNeverQualifiesAnyDistanceGatedRule() {
        let candidate = makeCandidate(overnightCount: 1, maxDistanceFromHomeKm: nil, totalSessionCount: 5, durationHours: 10)
        let decision = DefaultTripEligibilityEvaluator().evaluate(candidate: candidate, config: .default)
        #expect(!decision.isEligible)
    }
}
