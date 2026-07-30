//
//  LayoutSwatchPhotoProvider.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/30/26.
//

import SwiftUI

/// Colored gradient placeholder for one slot, keyed by a stable hash of the photo reference's own
/// id — never real photo pixels, just a distinguishable color per slot. Same palette/stable-hash
/// technique `DistinguishableMockPhotoProvider` (Features/AlbumCreation, the Album Draft Planner's
/// own mock previews) already uses, kept here as its own lightweight sibling since this context
/// (a bare `AlbumPageLayout` picker, no actual photos assigned yet) has no `AlbumPlanningPhoto` to
/// key off of — just each slot's own id. Used by `AlbumPageViewer`'s inline layout picker (§
/// layout request: "Hiển thị các layout với phần ảnh có màu sắc giống phần Album Draft Planner").
struct LayoutSwatchPhotoProvider: AlbumSlotPhotoProviding {
    private static let styles: [[Color]] = [
        [.blue, .indigo], [.orange, .red], [.teal, .cyan], [.purple, .pink],
        [.green, .mint], [.yellow, .orange], [.indigo, .purple], [.red, .pink],
    ]

    func photoView(reference: AlbumPhotoReference, crop: AlbumPhotoCrop, contentMode: AlbumSlotContentMode) -> some View {
        let colors = Self.styles[Self.stableHashIndex(reference.id, count: Self.styles.count)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// FNV-1a over Unicode scalars — deterministic across launches, unlike `hashValue` (same
    /// reasoning `DistinguishableMockPhotoProvider` documents).
    private static func stableHashIndex(_ string: String, count: Int) -> Int {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for scalar in string.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Int(hash % UInt64(count))
    }
}
