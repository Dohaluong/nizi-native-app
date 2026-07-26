//
//  PhotoImportance.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// A single scoring criterion's contribution to a photo's importance — `code`/`score` rather
/// than an associated-value enum, since this needs to round-trip through `Codable`/persistence
/// cleanly (§ 6.2: "Nếu enum associated values gây khó encode... Ưu tiên cấu trúc ổn định cho
/// persistence").
struct PhotoImportanceReason: Codable, Hashable, Sendable {
    let code: String
    let score: Double

    static func favorite(_ score: Double) -> PhotoImportanceReason { .init(code: "favorite", score: score) }
    static func resolution(_ score: Double) -> PhotoImportanceReason { .init(code: "resolution", score: score) }
    static func edited(_ score: Double) -> PhotoImportanceReason { .init(code: "edited", score: score) }
    static func timelinePosition(_ score: Double) -> PhotoImportanceReason { .init(code: "timelinePosition", score: score) }
    static func orientation(_ score: Double) -> PhotoImportanceReason { .init(code: "orientation", score: score) }
    static func hasLocation(_ score: Double) -> PhotoImportanceReason { .init(code: "hasLocation", score: score) }
}

/// A photo's overall importance — heuristic-only this sprint (§ 6.1), computed once by
/// `PhotoImportanceEvaluating` before planning starts, then read (never recomputed) by the Cover
/// Selector, hero slot assignment, and layout-pair scoring.
struct PhotoImportance: Codable, Hashable, Sendable {
    let totalScore: Double
    let reasons: [PhotoImportanceReason]

    static let zero = PhotoImportance(totalScore: 0, reasons: [])
}
