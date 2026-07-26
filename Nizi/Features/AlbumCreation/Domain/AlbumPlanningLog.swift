//
//  AlbumPlanningLog.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Which stage of the planning pipeline an `AlbumPlanningLogEntry` came from. See
/// docs/specs/SPEC-ALBUM-PLANNER.md § 7.
enum AlbumPlanningStage: String, Codable, Sendable, CaseIterable {
    case input
    case location
    case importance
    case cover
    case grouping
    case spread
    case layoutSelection
    case assignment
    case validation
    case persistence
}

enum AlbumPlanningLogLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}

/// One structured planning decision/event. `code` and `metadata` are the stable, machine-usable
/// data; `message` is a human-readable summary for debug/Preview display only — nothing re-parses
/// `message` to recover data (§ 7.2: "Không parse lại message để lấy dữ liệu").
struct AlbumPlanningLogEntry: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let stage: AlbumPlanningStage
    let level: AlbumPlanningLogLevel

    let subjectId: String?
    let code: String
    let message: String

    let metadata: [String: String]

    init(
        stage: AlbumPlanningStage,
        level: AlbumPlanningLogLevel = .info,
        subjectId: String? = nil,
        code: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        id = "\(stage.rawValue)-\(code)-\(UUID().uuidString)"
        self.stage = stage
        self.level = level
        self.subjectId = subjectId
        self.code = code
        self.message = message
        self.metadata = metadata
    }
}

struct AlbumPlanningLog: Codable, Hashable, Sendable {
    var entries: [AlbumPlanningLogEntry] = []

    mutating func add(_ entry: AlbumPlanningLogEntry) {
        entries.append(entry)
    }

    func entries(in stage: AlbumPlanningStage) -> [AlbumPlanningLogEntry] {
        entries.filter { $0.stage == stage }
    }
}
