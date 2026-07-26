//
//  AlbumPageRenderer.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import SwiftUI

/// The one renderer every layout goes through — no `switch photoCount` building bespoke
/// SwiftUI per photo count anywhere in the app (see docs/ALBUM_LAYOUT_SYSTEM.md § Renderer).
///
/// Responsibilities (and *only* these — § 12.1): scale `layout.referenceCanvas` to whatever size
/// it's actually given, position each slot, show the assigned photo or a placeholder, clip to
/// the slot, apply corner radius. It never decides which layout to use, never sorts/assigns
/// photos, never loads JSON, and never contains Album business logic — all of that is the
/// caller's job (layout selection, assignment editing, persistence).
struct AlbumPageRenderer<Provider: AlbumSlotPhotoProviding>: View {
    let layout: AlbumPageLayout
    let assignments: [AlbumPhotoAssignment]
    let photoProvider: Provider
    /// § 12.4 — debug/preview only.
    var showsDebugSlotIds: Bool = false
    /// Presentation-only hook, nil by default so every existing caller (gallery/layout previews,
    /// edit sheets) is unaffected — when set, tapping a slot that has a real photo assigned (never
    /// an empty placeholder) invokes this instead of the renderer doing anything with the tap
    /// itself. No gesture is attached at all when this is nil, so callers that wrap the renderer in
    /// their own `Button` (e.g. layout pickers) keep working exactly as before.
    var onTapPhoto: ((AlbumPhotoAssignment) -> Void)? = nil

    var body: some View {
        // A single `GeometryReader` at the canvas level (§ Performance) — no nested
        // `GeometryReader`s per slot; every slot's frame is plain arithmetic from this one size.
        GeometryReader { proxy in
            let scaleX = proxy.size.width / layout.referenceCanvas.width
            let scaleY = proxy.size.height / layout.referenceCanvas.height
            // Built once per render pass, not re-searched per slot (§ Performance).
            let assignmentsBySlotId = Dictionary(uniqueKeysWithValues: assignments.map { ($0.slotId, $0) })

            ZStack(alignment: .topLeading) {
                backgroundView

                ForEach(layout.slots.sorted { $0.order < $1.order }) { slot in
                    slotView(slot, scaleX: scaleX, scaleY: scaleY, assignmentsBySlotId: assignmentsBySlotId)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var backgroundView: some View {
        switch layout.background.type {
        case .solid:
            Color(hex: layout.background.value) ?? Color(.systemBackground)
        }
    }

    private func slotView(
        _ slot: AlbumLayoutSlot,
        scaleX: CGFloat,
        scaleY: CGFloat,
        assignmentsBySlotId: [String: AlbumPhotoAssignment]
    ) -> some View {
        let actualWidth = slot.frame.width * scaleX
        let actualHeight = slot.frame.height * scaleY
        let actualX = slot.frame.x * scaleX
        let actualY = slot.frame.y * scaleY
        // Uniform scale for the radius so it doesn't stretch unevenly on a non-uniformly scaled
        // canvas (portrait/landscape formats can have scaleX != scaleY).
        let scaledCornerRadius = slot.cornerRadius * min(scaleX, scaleY)
        let assignment = assignmentsBySlotId[slot.id]

        return Group {
            if let onTapPhoto, let assignment {
                slotContent(slot: slot, assignment: assignment, cornerRadius: scaledCornerRadius)
                    .contentShape(Rectangle())
                    .onTapGesture { onTapPhoto(assignment) }
            } else {
                slotContent(slot: slot, assignment: assignment, cornerRadius: scaledCornerRadius)
            }
        }
        // Container (this exact frame) owns the size — the photo/placeholder inside only
        // fills or fits it, never the reverse (§ Container owns size).
        .frame(width: actualWidth, height: actualHeight)
        .position(x: actualX + actualWidth / 2, y: actualY + actualHeight / 2)
    }

    private func slotContent(slot: AlbumLayoutSlot, assignment: AlbumPhotoAssignment?, cornerRadius: CGFloat) -> some View {
        AlbumPhotoSlotView(
            slot: slot,
            assignment: assignment,
            photoProvider: photoProvider,
            cornerRadius: cornerRadius,
            showsDebugSlotId: showsDebugSlotIds
        )
    }
}

private extension Color {
    /// Minimal `"#RRGGBB"` parser — the only background kind this sprint supports (§ Background).
    init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.removeAll { $0 == "#" }
        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
