//
//  LayoutSwatchPhotoProvider.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/30/26.
//

import SwiftUI

/// Gradient placeholder for one slot — never real photo pixels, just a soft, consistent stand-in.
/// Used by `AlbumPageViewer`'s inline layout picker (§ layout request: "chuyển thành màu xanh lam
/// #2196F3 gradient nhẹ" — one calm blue gradient for every slot instead of the old per-slot
/// hashed color palette).
struct LayoutSwatchPhotoProvider: AlbumSlotPhotoProviding {
    private static let brandBlue = Color(albumHex: "#2196F3") ?? .blue
    private static let colors: [Color] = [brandBlue.opacity(0.55), brandBlue.opacity(0.25)]

    func photoView(reference: AlbumPhotoReference, crop: AlbumPhotoCrop, contentMode: AlbumSlotContentMode) -> some View {
        LinearGradient(colors: Self.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
