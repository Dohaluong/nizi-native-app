//
//  CurationRejectionReason.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import Foundation

/// Why a photo isn't (or is no longer) part of the auto-selected highlights — stamped at
/// curation time so Curation Diagnostics can answer "why was this rejected?" long after the
/// in-memory Vision analysis that produced it is gone (there's no persistent Vision cache this
/// sprint — see docs/sprint/SPRINT-SMART-EVENT-HIGHLIGHTS.md § 43). Deliberately does not include
/// a `.userRemoved` case — that's already fully expressed by `SelectionSource`, and combining the
/// two is a Presentation-layer display concern, not a Domain one.
enum CurationRejectionReason: String, Equatable, Codable {
    case screenshot
    case document
    case lowQuality
    case nearDuplicate
    case globalDuplicate
    case trimmed
}
