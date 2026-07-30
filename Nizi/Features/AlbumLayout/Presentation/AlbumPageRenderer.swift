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
    /// § user request "Thêm chữ" — real, per-Page content for the layout's text blocks (keyed by
    /// `AlbumTextAssignment.textBlockId`). Defaults to `[]` so every existing caller (gallery/
    /// layout previews, layout-picker swatches) is unaffected — a layout with no text blocks never
    /// reads this at all, and even a layout that does just shows every block's own placeholder.
    var textAssignments: [AlbumTextAssignment] = []
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
    /// § user request — quick-tap (not held) a slot's photo to open a crop editor for it, reported
    /// alongside the on-screen aspect ratio (`rect.width / rect.height`) of the slot it's currently
    /// in — the crop editor defaults its own frame to that same ratio ("Khung crop mặc định bằng
    /// tỉ lệ frame chứa ảnh"). `nil` (the default) attaches no tap-detection at all; same opt-in
    /// shape as `onSwapPhotos`.
    var onCropPhoto: ((_ assignment: AlbumPhotoAssignment, _ frameAspectRatio: CGFloat) -> Void)? = nil
    /// § user request — reports whenever a drag-to-swap goes from not-picked-up to picked-up (or
    /// back). The caller uses this to lock `TabView(.page)`'s own paging out for as long as a
    /// drag is actually in flight (see `AlbumPagingLockView` — SwiftUI-level gesture priority
    /// can't retroactively steal a touch already being tracked by `UIPageViewController`'s own
    /// internal pan recognizer, so that lock has to reach into UIKit directly instead).
    var onDragActiveChanged: ((Bool) -> Void)? = nil
    /// § user request — quick-tap a text block to edit its content and style, reported as the
    /// *effective* `AlbumTextAssignment` currently in play for it — either the Page's own real
    /// assignment, or (if it doesn't have one yet) a synthesized one seeded from the layout's
    /// `AlbumTextBlock` default style with empty text, so the edit screen always opens pre-filled
    /// with whatever the block is actually showing right now. `nil` (the default) attaches no
    /// tap-detection at all; same opt-in shape as `onCropPhoto`.
    var onTapTextBlock: ((_ effective: AlbumTextAssignment) -> Void)? = nil

    @State private var dragState: AlbumSlotDragState?
    @State private var pendingPress: AlbumSlotPendingPress?
    @State private var activeRipples: [String: AlbumSlotRippleEffect] = [:]

    var body: some View {
        // A single `GeometryReader` at the canvas level (§ Performance) — no nested
        // `GeometryReader`s per slot; every slot's frame is plain arithmetic from this one size.
        GeometryReader { proxy in
            let scaleX = proxy.size.width / layout.referenceCanvas.width
            let scaleY = proxy.size.height / layout.referenceCanvas.height
            // Built once per render pass, not re-searched per slot (§ Performance).
            let assignmentsBySlotId = Dictionary(uniqueKeysWithValues: assignments.map { ($0.slotId, $0) })
            let textAssignmentsByBlockId = Dictionary(uniqueKeysWithValues: textAssignments.map { ($0.textBlockId, $0) })
            let slotFrames = slotFrames(scaleX: scaleX, scaleY: scaleY)
            // The swap gesture reports `.global` drag locations (see `albumSlotSwapGesture`'s own
            // doc comment for why not a named coordinate space) — this is what converts them back
            // to the same local space `slotFrames` is already in.
            let canvasOrigin = proxy.frame(in: .global).origin

            ZStack(alignment: .topLeading) {
                backgroundView

                // § user request — changing layout animates each photo *moving* from its old
                // slot's frame to its new one, not popping straight there. That only happens if
                // SwiftUI recognizes "this is still the same view, just with new frame/position
                // values" across the layout change — which means keying `ForEach` by the *photo's*
                // own stable id, not `slot.id` (every real layout independently names its own
                // slots "photo-1", "photo-2", ... — two different layouts' "photo-1" are not the
                // same slot, but the same photo re-assigned to a new layout's slot very much is
                // still "the same thing" that should visibly move rather than get torn down and
                // recreated in place).
                ForEach(renderableSlots(assignmentsBySlotId: assignmentsBySlotId)) { entry in
                    slotView(
                        entry.slot, assignmentsBySlotId: assignmentsBySlotId, slotFrames: slotFrames,
                        canvasOrigin: canvasOrigin, scaleX: scaleX, scaleY: scaleY
                    )
                }

                // § user request "Thêm chữ" — unlike slots there's nothing here that needs to
                // survive a layout change's animation or participate in the swap/crop gestures
                // above (a text block's content is looked up fresh by id every render, not
                // preserved/animated across a layout swap), so a plain `ForEach` keyed by the
                // block's own id is enough.
                ForEach(layout.textBlocks) { textBlock in
                    textBlockView(textBlock, textAssignmentsByBlockId: textAssignmentsByBlockId, scaleX: scaleX, scaleY: scaleY)
                }

                if let dragState {
                    AlbumSlotDragPreview(assignment: dragState.sourceAssignment, photoProvider: photoProvider, position: dragState.currentLocation)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onChange(of: dragState != nil) { _, isActive in
            onDragActiveChanged?(isActive)
        }
    }

    private var backgroundView: some View {
        switch layout.background.type {
        case .solid:
            Color(hex: layout.background.value) ?? Color(.systemBackground)
        }
    }

    /// `id` is the assigned photo's own id when there is one — stable across a layout change,
    /// since `AlbumEditActionApplying.changePageLayout` re-assigns photos onto new slot ids but
    /// preserves which *photos* are on the Page. Empty slots (no assignment) have nothing to stay
    /// stable across a layout change anyway, so they just key off the slot's own id.
    private struct RenderableSlot: Identifiable {
        let id: String
        let slot: AlbumLayoutSlot
    }

    private func renderableSlots(assignmentsBySlotId: [String: AlbumPhotoAssignment]) -> [RenderableSlot] {
        layout.slots.sorted { $0.order < $1.order }.map { slot in
            RenderableSlot(id: assignmentsBySlotId[slot.id]?.photo.id ?? "empty-\(slot.id)", slot: slot)
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

    private func textBlockFrame(_ textBlock: AlbumTextBlock, scaleX: CGFloat, scaleY: CGFloat) -> CGRect {
        CGRect(
            x: textBlock.frame.x * scaleX, y: textBlock.frame.y * scaleY,
            width: textBlock.frame.width * scaleX, height: textBlock.frame.height * scaleY
        )
    }

    private func textBlockView(
        _ textBlock: AlbumTextBlock,
        textAssignmentsByBlockId: [String: AlbumTextAssignment],
        scaleX: CGFloat,
        scaleY: CGFloat
    ) -> some View {
        let rect = textBlockFrame(textBlock, scaleX: scaleX, scaleY: scaleY)
        let assignment = textAssignmentsByBlockId[textBlock.id]
        // § user request — the Page's own assignment (once one exists) is the *actual* style in
        // use, which can differ from the layout's own default once a real Album's user picks
        // something different in the edit screen — falls back to the block's own default only
        // for a Page that doesn't have an assignment yet at all.
        let horizontalAlignment = assignment?.horizontalAlignment ?? textBlock.horizontalAlignment
        let verticalAlignment = assignment?.verticalAlignment ?? textBlock.verticalAlignment
        let fontFamily = assignment?.fontFamily ?? textBlock.fontFamily
        let fontSize = assignment?.fontSize ?? textBlock.fontSize
        let fontStyle = assignment?.fontStyle ?? textBlock.fontStyle
        // Uniform scale, same reasoning `scaledCornerRadius` already uses for slots — never
        // stretch the text unevenly on a non-uniformly scaled canvas.
        let scaledFontSize = fontSize * min(scaleX, scaleY)

        let content = AlbumTextBlockView(
            frame: rect, horizontalAlignment: horizontalAlignment, verticalAlignment: verticalAlignment,
            fontFamily: fontFamily, scaledFontSize: scaledFontSize, fontStyle: fontStyle,
            content: assignment?.text
        )

        return Group {
            if let onTapTextBlock {
                let effective = assignment ?? AlbumTextAssignment(
                    id: "pending-\(textBlock.id)", textBlockId: textBlock.id, text: "",
                    horizontalAlignment: horizontalAlignment, verticalAlignment: verticalAlignment,
                    fontFamily: fontFamily, fontSize: fontSize, fontStyle: fontStyle
                )
                content
                    .contentShape(Rectangle())
                    .onTapGesture { onTapTextBlock(effective) }
            } else {
                content
            }
        }
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
                    // `.fill(style: FillStyle(eoFill: true))` is required here — `.mask(shape)`
                    // alone renders the shape with the *default* (nonzero) fill rule, under which
                    // a rect containing a circle just fills solid (the circle sub-path adds
                    // nothing new to the union), so this was masking in the *entire* frozen photo
                    // for the whole animation with no hole ever appearing, then vanishing outright
                    // the instant `activeRipples` cleared — a hard cut with no visible transition,
                    // not the growing "sóng nước" reveal this is supposed to be.
                    .mask(AlbumSlotRippleMask(center: ripple.anchor, radius: ripple.radius).fill(style: FillStyle(eoFill: true)))
                    .allowsHitTesting(false)
            }
        }
        // Container (this exact frame) owns the size — the photo/placeholder inside only
        // fills or fits it, never the reverse (§ Container owns size).
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        // § user report — position wasn't animating at all, and size only animated growing, not
        // shrinking: relying solely on the *caller's* `withAnimation` (in `AlbumPageViewer.apply`)
        // to propagate all the way down through this `GeometryReader` → `ZStack` → `ForEach` →
        // conditional `@ViewBuilder` branches → custom gesture-modifier chain was unreliable in
        // practice. An explicit, local `.animation(_:value:)` tied directly to `rect` guarantees
        // both `.frame` and `.position` always animate together whenever this slot's own target
        // geometry actually changes, independent of whether an ambient transaction survived that
        // whole chain intact.
        .animation(.easeInOut(duration: 0.35), value: rect)
        .albumSlotSwapGesture(
            isEnabled: onSwapPhotos != nil || onCropPhoto != nil,
            canSwap: onSwapPhotos != nil,
            slot: slot, assignment: assignment, slotRect: rect, slotFrames: slotFrames,
            assignmentsBySlotId: assignmentsBySlotId,
            dragState: $dragState,
            pendingPress: $pendingPress,
            canvasOrigin: canvasOrigin,
            onDropped: { source, target in beginSwapRipple(source: source, target: target) },
            onTap: onCropPhoto != nil ? { tapped in onCropPhoto?(tapped, rect.width / rect.height) } : nil
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
