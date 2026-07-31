//
//  SourceAssetFingerprint.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import CryptoKit
import Foundation

/// Deterministic, order-independent identity for an Event's current asset membership — used so
/// curation cache-validity can detect "same count, different actual assets" (e.g. one photo
/// removed, a different one added — count unchanged, membership isn't). See
/// docs/sprint/SPRINT-SMART-EVENT-HIGHLIGHTS.md § 9-11.
///
/// Deliberately not Swift's `Hasher`/`hashValue`: those are randomly reseeded every process
/// launch, so a fingerprint computed at save time would never match on the next app launch —
/// the cache would look valid in a single run's tests and silently never hit in production.
/// `CryptoKit` is a system framework already linked everywhere; no cryptographic strength is
/// required here, only a stable, deterministic digest.
enum SourceAssetFingerprint {
    static func compute(assetIDs: [String]) -> String {
        let joined = assetIDs.sorted().joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
