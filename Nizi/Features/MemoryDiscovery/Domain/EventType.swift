//
//  EventType.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// See docs/modules/memory-discovery/SPEC.md § 11 — MVP intentionally doesn't try to
/// recognize birthdays, holidays, or weddings; those stay `.dayEvent` or `.unknown`.
enum EventType: String, Equatable, Hashable {
    case trip
    case dayEvent
    case weekend
    case unknown
}
