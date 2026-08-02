//
//  EventVisibility.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import Foundation

/// How prominently an Event should surface in the UX — set once by `FastEventQualityService`
/// right after Event Discovery, never by deleting/merging/rebuilding the Event itself. See
/// docs/sprint/SPRINT-FAST-EVENT-QUALITY.md § 7/§ 9/§ 14.
enum EventVisibility: String, Equatable {
    case normal
    case lowValue
    case hiddenNoise
}
