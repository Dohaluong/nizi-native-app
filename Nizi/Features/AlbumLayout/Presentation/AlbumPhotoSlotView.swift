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
        ZStack {
            Group {
                if let assignment {
                    photoProvider.photoView(reference: assignment.photo, crop: assignment.crop, contentMode: slot.contentMode)
                } else {
                    placeholder
                }
            }
            // § user request — "phần ảnh cho phép chọn option gradient đen trong suốt, mục đích
            // làm nền cho chữ": painted on top of the photo/placeholder, inside the same clip, so
            // it never bleeds outside the slot's own rounded rect.
            if let overlay = slot.gradientOverlay {
                LinearGradient(stops: overlay.gradientStops, startPoint: overlay.edge.gradientStartPoint, endPoint: overlay.edge.gradientEndPoint)
                    .allowsHitTesting(false)
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

private extension AlbumGradientEdge {
    /// `.top`/`.bottom` fade along the vertical axis, `.left`/`.right` along the horizontal one —
    /// mirrors `AlbumSlotGradientOverlay`'s own doc comment ("height for top/bottom, width for
    /// left/right").
    var gradientStartPoint: UnitPoint {
        switch self {
        case .top, .bottom: return .top
        case .left, .right: return .leading
        }
    }

    var gradientEndPoint: UnitPoint {
        switch self {
        case .top, .bottom: return .bottom
        case .left, .right: return .trailing
        }
    }
}

private extension AlbumSlotGradientOverlay {
    /// § "Ví dụ 30%-Dưới thì khoảng gradien chuyển từ đen 100% về 0% trong 30% chiều cao từ dưới
    /// lên": `edge` is darkest at its own 0/1 end of the gradient's own axis, fading to fully
    /// transparent by `extentPercent` of the way across — the remaining stretch back to the
    /// opposite edge stays flat transparent (a third stop, not just two, is what pins that "no
    /// gradient beyond here" boundary in place instead of letting `LinearGradient` interpolate the
    /// whole span).
    var gradientStops: [Gradient.Stop] {
        let extent = min(max(extentPercent / 100, 0), 1)
        let dark = Color.black.opacity(min(max(opacity, 0), 1))
        switch edge {
        case .top:
            return [.init(color: dark, location: 0), .init(color: .clear, location: extent), .init(color: .clear, location: 1)]
        case .bottom:
            return [.init(color: .clear, location: 0), .init(color: .clear, location: 1 - extent), .init(color: dark, location: 1)]
        case .left:
            return [.init(color: dark, location: 0), .init(color: .clear, location: extent), .init(color: .clear, location: 1)]
        case .right:
            return [.init(color: .clear, location: 0), .init(color: .clear, location: 1 - extent), .init(color: dark, location: 1)]
        }
    }
}
