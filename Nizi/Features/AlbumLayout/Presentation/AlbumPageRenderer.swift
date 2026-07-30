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
/// caller's job (layout selection, assignment editing, persistence). The drag-to-swap gesture
/// (`onSwapPhotos`) is the one exception carved out deliberately: it's pure geometry/gesture
/// work this view already has every slot's frame for, and it never decides *what* a swap means —
/// it only reports "the user dragged this photo onto that one," the same "presentation hook,
/// caller owns the actual mutation" shape `onTapPhoto` already uses.
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
    /// § user request — long-press a slot's photo, drag it onto another slot, release to swap
    /// both. `nil` (the default) attaches no gesture at all, same opt-in shape `onTapPhoto`
    /// already uses; the caller is responsible for the actual data mutation (e.g.
    /// `AlbumEditAction.swapPhotos`) and for only ever passing this while actively editing.
    var onSwapPhotos: ((_ from: AlbumPhotoAssignment, _ to: AlbumPhotoAssignment) -> Void)? = nil

    @State private var dragState: AlbumSlotDragState?
    @State private var activeRipples: [String: AlbumSlotRippleEffect] = [:]

    var body: some View {
        // A single `GeometryReader` at the canvas level (§ Performance) — no nested
        // `GeometryReader`s per slot; every slot's frame is plain arithmetic from this one size.
        GeometryReader { proxy in
            let scaleX = proxy.size.width / layout.referenceCanvas.width
            let scaleY = proxy.size.height / layout.referenceCanvas.height
            // Built once per render pass, not re-searched per slot (§ Performance).
            let assignmentsBySlotId = Dictionary(uniqueKeysWithValues: assignments.map { ($0.slotId, $0) })
            let slotFrames = slotFrames(scaleX: scaleX, scaleY: scaleY)
            // The swap gesture reports `.global` drag locations (see `albumSlotSwapGesture`'s own
            // doc comment for why not a named coordinate space) — this is what converts them back
            // to the same local space `slotFrames` is already in.
            let canvasOrigin = proxy.frame(in: .global).origin

            ZStack(alignment: .topLeading) {
                backgroundView

                ForEach(layout.slots.sorted { $0.order < $1.order }) { slot in
                    slotView(
                        slot, assignmentsBySlotId: assignmentsBySlotId, slotFrames: slotFrames,
                        canvasOrigin: canvasOrigin, scaleX: scaleX, scaleY: scaleY
                    )
                }

                if let dragState {
                    AlbumSlotDragPreview(assignment: dragState.sourceAssignment, photoProvider: photoProvider, position: dragState.currentLocation)
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

    /// Every slot's on-screen rect, keyed by slot id — computed once per render pass and shared
    /// by both slot placement and the drag gesture's own drop-target hit test, so the two can
    /// never disagree about where a slot actually is.
    private func slotFrames(scaleX: CGFloat, scaleY: CGFloat) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: layout.slots.map { slot in
            let rect = CGRect(
                x: slot.frame.x * scaleX, y: slot.frame.y * scaleY,
                width: slot.frame.width * scaleX, height: slot.frame.height * scaleY
            )
            return (slot.id, rect)
        })
    }

    private func slotView(
        _ slot: AlbumLayoutSlot,
        assignmentsBySlotId: [String: AlbumPhotoAssignment],
        slotFrames: [String: CGRect],
        canvasOrigin: CGPoint,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) -> some View {
        let rect = slotFrames[slot.id] ?? .zero
        // Uniform scale for the radius so it doesn't stretch unevenly on a non-uniformly scaled
        // canvas (portrait/landscape formats can have scaleX != scaleY).
        let scaledCornerRadius = slot.cornerRadius * min(scaleX, scaleY)
        let assignment = assignmentsBySlotId[slot.id]

        return ZStack {
            Group {
                if let onTapPhoto, let assignment {
                    slotContent(slot: slot, assignment: assignment, cornerRadius: scaledCornerRadius)
                        .contentShape(Rectangle())
                        .onTapGesture { onTapPhoto(assignment) }
                } else {
                    slotContent(slot: slot, assignment: assignment, cornerRadius: scaledCornerRadius)
                }
            }
            // § "Khung của ảnh cũ sẽ mờ đi" — the slot a drag started from dims while it's in
            // flight, so it's visually clear which photo is "picked up."
            .opacity(dragState?.sourceSlotId == slot.id ? 0.35 : 1)

            // § "Hiệu ứng ảnh là vòng tròn mở to dần ... Khung ảnh cũ cũng hiện ảnh đổi" — both
            // slots involved in a just-completed swap show their *own former* photo on top,
            // punched away by a growing circle to reveal the new (swapped-in) photo already
            // arriving underneath via the normal `assignments` prop.
            if let ripple = activeRipples[slot.id] {
                slotContent(slot: slot, assignment: ripple.frozenAssignment, cornerRadius: scaledCornerRadius)
                    .mask(AlbumSlotRippleMask(center: ripple.anchor, radius: ripple.radius))
                    .allowsHitTesting(false)
            }
        }
        // Container (this exact frame) owns the size — the photo/placeholder inside only
        // fills or fits it, never the reverse (§ Container owns size).
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .albumSlotSwapGesture(
            isEnabled: onSwapPhotos != nil,
            slot: slot, assignment: assignment, slotRect: rect, slotFrames: slotFrames,
            assignmentsBySlotId: assignmentsBySlotId,
            dragState: $dragState,
            canvasOrigin: canvasOrigin,
            onDropped: { source, target in beginSwapRipple(source: source, target: target) }
        )
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

    /// Starts both slots' reveal transitions immediately (never waiting for the caller's async
    /// mutation to land — by the time it does, on the next render pass or two, the frozen top
    /// layer already matches whatever's arriving underneath, so there's nothing to visually
    /// reconcile) and reports the swap to the caller.
    private func beginSwapRipple(source: AlbumSlotSwapEndpoint, target: AlbumSlotSwapEndpoint) {
        activeRipples[source.slotId] = AlbumSlotRippleEffect(
            frozenAssignment: source.assignment, anchor: source.anchor, radius: 0,
            maxRadius: hypot(source.rect.width, source.rect.height)
        )
        activeRipples[target.slotId] = AlbumSlotRippleEffect(
            frozenAssignment: target.assignment, anchor: target.anchor, radius: 0,
            maxRadius: hypot(target.rect.width, target.rect.height)
        )

        withAnimation(.easeOut(duration: 0.6)) {
            activeRipples[source.slotId]?.radius = activeRipples[source.slotId]?.maxRadius ?? 0
            activeRipples[target.slotId]?.radius = activeRipples[target.slotId]?.maxRadius ?? 0
        }

        let sourceSlotId = source.slotId
        let targetSlotId = target.slotId
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            activeRipples[sourceSlotId] = nil
            activeRipples[targetSlotId] = nil
        }

        onSwapPhotos?(source.assignment, target.assignment)
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
