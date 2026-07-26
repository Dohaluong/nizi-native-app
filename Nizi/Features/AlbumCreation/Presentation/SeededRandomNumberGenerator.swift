//
//  SeededRandomNumberGenerator.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// A small deterministic PRNG (splitmix64) — `SystemRandomNumberGenerator` has no settable seed,
/// so it can't reproduce a specific mock album across runs. Preview/Diagnostics only (docs/specs/
/// SPEC-MODIFY-DRAFT.md § 2: "Random chỉ được dùng trong Preview, Diagnostics, Mock data factory").
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
