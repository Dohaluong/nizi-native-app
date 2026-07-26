//
//  DiscoveryReason.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import Foundation

/// Typed tag behind each reason string, so tests can assert "a favorites reason is present"
/// without string-matching Vietnamese copy. See docs/philosophy/PRODUCT-PHILOSOPHY.md § 7
/// (Explainable suggestions) — every candidate must carry at least one of these.
enum DiscoveryReasonKind: String, Equatable {
    case assetCountOverDuration
    case sameAreaMajority
    case multipleSessions
    case favoritesPresent
}

struct DiscoveryReason: Identifiable, Equatable, Hashable {
    var id: String { "\(kind.rawValue)-\(text)" }
    let kind: DiscoveryReasonKind
    let text: String
}
