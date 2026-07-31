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
    /// tap-detection at all; same opt-in shape as `onCropPhoto`. `kind` is the block's own
    /// template-level `AlbumTextBlockKind` (never per-Page, see that type's own doc comment) —
    /// passed alongside so the edit screen's live preview can show the same kind-specific
    /// placeholder the real Page does while its content is still empty.
    var onTapTextBlock: ((_ effective: AlbumTextAssignment, _ kind: AlbumTextBlockKind) -> Void)? = nil

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

                // A rendered element represents a *slot*, so its identity must be that slot's
                // id.  In particular, `photo.id` is not a valid identity here: an Album may use
                // the same photo in more than one slot, and a photo can move to another slot when
                // the layout changes. Either case lets SwiftUI reuse a gesture recognizer with a
                // closure captured for a different assignment. That manifested as every tap after
                // returning from Crop opening one previously tapped photo.
                ForEach(renderableSlots(assignmentsBySlotId: assignmentsBySlotId)) { entry in
                    // Each element has both a concrete per-slot View and an unambiguous slot
                    // identity. This keeps a slot's gesture closure tied to its assignment across
                    // a Crop navigation round-trip and other renderer updates.
                    let rect = slotFrames[entry.slot.id] ?? .zero
                    SlotContainerView(
                        slot: entry.slot,
                        assignment: assignmentsBySlotId[entry.slot.id],
                        rect: rect,
                        // Uniform scale for the radius so it doesn't stretch unevenly on a
                        // non-uniformly scaled canvas (portrait/landscape can have scaleX != scaleY).
                        scaledCornerRadius: entry.slot.cornerRadius * min(scaleX, scaleY),
                        photoProvider: photoProvider,
                        showsDebugSlotIds: showsDebugSlotIds,
                        ripple: activeRipples[entry.slot.id],
                        // § "Khung của ảnh cũ sẽ mờ đi" — the slot a drag started from dims while
                        // it's in flight, so it's visually clear which photo is "picked up."
                        isDimmedForDrag: dragState?.sourceSlotId == entry.slot.id,
                        onTapPhoto: onTapPhoto, onSwapPhotos: onSwapPhotos, onCropPhoto: onCropPhoto,
                        slotFrames: slotFrames, assignmentsBySlotId: assignmentsBySlotId, canvasOrigin: canvasOrigin,
                        dragState: $dragState, pendingPress: $pendingPress,
                        onDropped: { source, target in beginSwapRipple(source: source, target: target) }
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
            Color(albumHex: layout.background.value) ?? Color(.systemBackground)
        }
    }

    /// The identity is deliberately the layout slot id. Layout validation guarantees it is unique
    /// within a Page, whereas a photo reference is allowed to appear in multiple assignments.
    private struct RenderableSlot: Identifiable {
        let id: String
        let slot: AlbumLayoutSlot
    }

    private func renderableSlots(assignmentsBySlotId: [String: AlbumPhotoAssignment]) -> [RenderableSlot] {
        layout.slots.sorted { $0.order < $1.order }.map { slot in
            RenderableSlot(id: slot.id, slot: slot)
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
        let textColor = assignment?.textColor ?? textBlock.textColor
        // Uniform scale, same reasoning `scaledCornerRadius` already uses for slots — never
        // stretch the text unevenly on a non-uniformly scaled canvas.
        let scaledFontSize = fontSize * min(scaleX, scaleY)

        let content = AlbumTextBlockView(
            size: rect.size, horizontalAlignment: horizontalAlignment, verticalAlignment: verticalAlignment,
            fontFamily: fontFamily, scaledFontSize: scaledFontSize, fontStyle: fontStyle, textColor: textColor,
            kind: textBlock.kind, content: assignment?.text
        )

        // § bug report — "khi ấn vào ảnh cũng ra editor text": the gesture must attach *before*
        // `.position()` (applied once, below, to both branches) — see `AlbumTextBlockView`'s own
        // doc comment for why attaching it to an already-positioned view silently made the tap
        // target cover the whole canvas instead of just this block's own bounds. Mirrors
        // `slotView`'s exact structure below.
        return Group {
            if let onTapTextBlock {
                let effective = assignment ?? AlbumTextAssignment(
                    id: "pending-\(textBlock.id)", textBlockId: textBlock.id, text: "",
                    horizontalAlignment: horizontalAlignment, verticalAlignment: verticalAlignment,
                    fontFamily: fontFamily, fontSize: fontSize, fontStyle: fontStyle, textColor: textColor
                )
                content
                    .contentShape(Rectangle())
                    .onTapGesture { onTapTextBlock(effective, textBlock.kind) }
            } else {
                content
            }
        }
        .position(x: rect.midX, y: rect.midY)
    }

    /// One slot's rendered content + gesture, as a real, concrete `View` type — not a plain
    /// function called inline in `ForEach` (see the call site's own doc comment for why that
    /// distinction is what actually fixed § user report "khoảng tác động bị ảnh hưởng sang frame
    /// khác"). Every stored property here is a plain value/closure capture except `dragState`/
    /// `pendingPress`, which stay `@Binding` back to `AlbumPageRenderer`'s own `@State` — cross-
    /// slot drag-to-swap tracking still genuinely needs that shared state; only the *view identity*
    /// wrapping it changed.
    private struct SlotContainerView<Provider: AlbumSlotPhotoProviding>: View {
        let slot: AlbumLayoutSlot
        let assignment: AlbumPhotoAssignment?
        let rect: CGRect
        let scaledCornerRadius: CGFloat
        let photoProvider: Provider
        let showsDebugSlotIds: Bool
        let ripple: AlbumSlotRippleEffect?
        let isDimmedForDrag: Bool
        let onTapPhoto: ((AlbumPhotoAssignment) -> Void)?
        let onSwapPhotos: ((_ from: AlbumPhotoAssignment, _ to: AlbumPhotoAssignment) -> Void)?
        let onCropPhoto: ((_ assignment: AlbumPhotoAssignment, _ frameAspectRatio: CGFloat) -> Void)?
        let slotFrames: [String: CGRect]
        let assignmentsBySlotId: [String: AlbumPhotoAssignment]
        let canvasOrigin: CGPoint
        @Binding var dragState: AlbumSlotDragState?
        @Binding var pendingPress: AlbumSlotPendingPress?
        let onDropped: (_ source: AlbumSlotSwapEndpoint, _ target: AlbumSlotSwapEndpoint) -> Void

        var body: some View {
            ZStack {
                Group {
                    if let onTapPhoto, let assignment {
                        content(for: assignment)
                            .contentShape(Rectangle())
                            .onTapGesture { onTapPhoto(assignment) }
                    } else {
                        content(for: assignment)
                    }
                }
                // § "Khung của ảnh cũ sẽ mờ đi" — the slot a drag started from dims while it's in
                // flight, so it's visually clear which photo is "picked up."
                .opacity(isDimmedForDrag ? 0.35 : 1)

                // § "Hiệu ứng ảnh là vòng tròn mở to dần ... Khung ảnh cũ cũng hiện ảnh đổi" — both
                // slots involved in a just-completed swap show their *own former* photo on top,
                // punched away by a growing circle to reveal the new (swapped-in) photo already
                // arriving underneath via the normal `assignments` prop.
                if let ripple {
                    content(for: ripple.frozenAssignment)
                        // `.fill(style: FillStyle(eoFill: true))` is required here — `.mask(shape)`
                        // alone renders the shape with the *default* (nonzero) fill rule, under
                        // which a rect containing a circle just fills solid (the circle sub-path
                        // adds nothing new to the union), so this was masking in the *entire*
                        // frozen photo for the whole animation with no hole ever appearing, then
                        // vanishing outright the instant the ripple cleared — a hard cut with no
                        // visible transition, not the growing "sóng nước" reveal this is supposed
                        // to be.
                        .mask(AlbumSlotRippleMask(center: ripple.anchor, radius: ripple.radius).fill(style: FillStyle(eoFill: true)))
                        .allowsHitTesting(false)
                }
            }
            // Container (this exact frame) owns the size — the photo/placeholder inside only
            // fills or fits it, never the reverse (§ Container owns size).
            .frame(width: rect.width, height: rect.height)
            // Hit testing must be defined while this view still has the slot's local bounds.
            // `position` is only placement in the canvas; attaching this gesture after it gives
            // SwiftUI the positioned layout container's bounds, which can be the entire canvas.
            // In a ZStack that made the topmost slot receive taps made over other slots.
            .contentShape(Rectangle())
            .albumSlotSwapGesture(
                isEnabled: onSwapPhotos != nil || onCropPhoto != nil,
                canSwap: onSwapPhotos != nil,
                slot: slot, assignment: assignment, slotRect: rect, slotFrames: slotFrames,
                assignmentsBySlotId: assignmentsBySlotId,
                dragState: $dragState,
                pendingPress: $pendingPress,
                canvasOrigin: canvasOrigin,
                onDropped: onDropped,
                onTap: onCropPhoto != nil ? { tapped in onCropPhoto?(tapped, rect.width / rect.height) } : nil
            )
            .position(x: rect.midX, y: rect.midY)
            // § user report — position wasn't animating at all, and size only animated growing,
            // not shrinking: relying solely on the *caller's* `withAnimation` (in `AlbumPageViewer
            // .apply`) to propagate all the way down through this `GeometryReader` → `ZStack` →
            // `ForEach` → conditional `@ViewBuilder` branches → custom gesture-modifier chain was
            // unreliable in practice. An explicit, local `.animation(_:value:)` tied directly to
            // `rect` guarantees both `.frame` and `.position` always animate together whenever
            // this slot's own target geometry actually changes, independent of whether an ambient
            // transaction survived that whole chain intact.
            .animation(.easeInOut(duration: 0.35), value: rect)
        }

        private func content(for assignment: AlbumPhotoAssignment?) -> some View {
            AlbumPhotoSlotView(
                slot: slot,
                assignment: assignment,
                photoProvider: photoProvider,
                cornerRadius: scaledCornerRadius,
                showsDebugSlotId: showsDebugSlotIds
            )
        }
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
