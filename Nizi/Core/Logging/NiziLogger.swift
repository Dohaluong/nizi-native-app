//
//  NiziLogger.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import OSLog

/// Category-scoped loggers for the app.
///
/// Never log GPS coordinates, photo content, people's names, embeddings, thumbnails,
/// or other sensitive metadata — see docs/modules/memory-discovery/ARCHITECTURE.md § 11
/// and docs/modules/memory-discovery/SPEC.md logging rules. Log event names and counts only.
enum NiziLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "vn.ima.Nizi"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let discovery = Logger(subsystem: subsystem, category: "memory-discovery")
    static let photoEditor = Logger(subsystem: subsystem, category: "photo-editor")
}
