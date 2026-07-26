//
//  PhotoPlaceDisplayNameBuilder.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Builds one clean, human-readable place string from placemark components — see
/// docs/specs/SPEC-ALBUM-PLANNER.md § 4.7:
///
/// ```text
/// Sydney Opera House + Sydney               → "Sydney Opera House, Sydney"
/// Hà Nội + Hà Nội + Việt Nam                → "Hà Nội, Việt Nam"
/// nil + Sydney + Australia                  → "Sydney, Australia"
/// nothing resolved                          → ""
/// ```
///
/// Never returns a fallback string like `"Unknown Location"` — an empty `displayName` is a
/// legitimate domain value; the UI layer decides how to present that.
struct PhotoPlaceDisplayNameBuilder {
    private static let maximumParts = 2

    func makeDisplayName(
        name: String?,
        subLocality: String?,
        locality: String?,
        administrativeArea: String?,
        country: String?
    ) -> String {
        // Most specific first — § 4.7 rule 3 ("ưu tiên địa điểm cụ thể").
        let candidates = [name, subLocality, locality, administrativeArea, country]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } // rule 1

        var parts: [String] = []
        for candidate in candidates {
            guard !parts.contains(candidate) else { continue } // rule 2
            parts.append(candidate)
            if parts.count == Self.maximumParts { break } // rule 4
        }

        return parts.joined(separator: ", ") // rule 5 — no trailing comma, since `parts` is already deduplicated/trimmed
    }
}
