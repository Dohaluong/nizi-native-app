//
//  AlbumPhotoSlotView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// One slot's content: the assigned photo, or a placeholder if none is assigned yet. Sizing and
/// positioning are the caller's (`AlbumPageRenderer`'s) responsibility via `.frame`/`.position` —
/// this view only fills whatever frame it's given (§ Container owns size).
struct AlbumPhotoSlotView<Provider: AlbumSlotPhotoProviding>: View {
    let slot: AlbumLayoutSlot
    let assignment: AlbumPhotoAssignment?
    let photoProvider: Provider
    /// Already scaled by the renderer from `slot.cornerRadius` — this view never does its own
    /// reference-canvas-to-actual-size scaling.
    let cornerRadius: CGFloat
    /// § 12.4 — debug/preview only; production call sites leave this `false`.
    var showsDebugSlotId: Bool = false

    var body: some View {
        Group {
            if let assignment {
                photoProvider.photoView(reference: assignment.photo, crop: assignment.crop, contentMode: slot.contentMode)
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        // No real photo metadata plumbed through yet (§ Accessibility) — this fallback
        // ("Photo N") is the whole requirement for this sprint. A future metadata source can
        // override it without changing this view's shape.
        .accessibilityLabel(accessibilityLabel)
    }

    private var placeholder: some View {
        ZStack {
            Color(.secondarySystemFill)
            VStack(spacing: 4) {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                if showsDebugSlotId {
                    Text(slot.id)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var accessibilityLabel: String {
        localizedString("album.layout.photo_number", defaultValue: "Photo \(slot.order + 1)")
    }
}
