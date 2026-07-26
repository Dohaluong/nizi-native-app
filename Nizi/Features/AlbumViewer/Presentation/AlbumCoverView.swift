//
//  AlbumCoverView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// Book-style cover — real cover photo, title, date/place, a light book frame (margin + shadow),
/// no 3D spine (docs/specs/SPEC-REAL-ALBUM.md § 13.2). Shown both as the Viewer's first item and
/// as the Album Detail hero.
struct AlbumCoverView: View {
    let configuration: AlbumCoverConfiguration

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AlbumPhotoView(reference: configuration.photo, crop: .centered, contentMode: .fill, targetSize: nil)

            LinearGradient(
                colors: [.clear, .black.opacity(0.15), .black.opacity(0.75)],
                startPoint: .center, endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                Text(configuration.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let dateText = configuration.dateText {
                    Text(dateText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(22)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [configuration.title]
        if let dateText = configuration.dateText { parts.append(dateText) }
        if let placeText = configuration.placeText, !placeText.isEmpty { parts.append(placeText) }
        return parts.joined(separator: ", ")
    }
}
