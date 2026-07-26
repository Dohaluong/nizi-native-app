//
//  DistinguishableMockPhotoProvider.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// A mock photo tile that's actually distinguishable from its neighbors — plain gray boxes made
/// it impossible to see which photo repeated, which was hero, or how a layout cropped things.
/// Style is derived from a *stable* hash of the photo ID (never `String.hashValue`, which isn't
/// stable across process launches — docs/specs/SPEC-MODIFY-DRAFT.md § 11), so the same photo ID
/// always renders the same way across regenerations that happen to reuse it, and never changes
/// mid-session on re-render. See docs/specs/SPEC-MODIFY-DRAFT.md § 11.
struct DistinguishableMockPhotoProvider: AlbumSlotPhotoProviding {
    let photosById: [String: AlbumPlanningPhoto]

    private static let styles: [[Color]] = [
        [.blue, .indigo], [.orange, .red], [.teal, .cyan], [.purple, .pink],
        [.green, .mint], [.yellow, .orange], [.indigo, .purple], [.red, .pink]
    ]

    func photoView(reference: AlbumPhotoReference, crop: AlbumPhotoCrop, contentMode: AlbumSlotContentMode) -> some View {
        let photoId = reference.id
        let colors = Self.styles[Self.stableHashIndex(photoId, count: Self.styles.count)]
        let photo = photosById[photoId]

        return ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 2) {
                Text(Self.shortLabel(for: photoId))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                if let orientation = photo?.orientation {
                    Text(orientation.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                }
                if let photo {
                    Text("Score \(Int(photo.importance.totalScore))")
                        .font(.system(size: 9))
                }
            }
            .foregroundStyle(.white)
            .shadow(radius: 1)
        }
    }

    /// `"preview-3-2"` → `"E3P2"` (Event 3, Photo 2) — falls back to a short prefix of the raw ID
    /// for anything that doesn't match this Preview-only ID shape.
    private static func shortLabel(for photoId: String) -> String {
        let parts = photoId.split(separator: "-")
        if parts.count == 3, parts[0] == "preview" {
            return "E\(parts[1])P\(parts[2])"
        }
        return String(photoId.prefix(6))
    }

    /// FNV-1a over Unicode scalars — deterministic across launches, unlike `hashValue`.
    private static func stableHashIndex(_ string: String, count: Int) -> Int {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for scalar in string.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Int(hash % UInt64(count))
    }
}
