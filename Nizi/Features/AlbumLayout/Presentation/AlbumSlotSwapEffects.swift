//
//  AlbumSlotSwapEffects.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/30/26.
//

import SwiftUI

/// Drag-to-swap support for `AlbumPageRenderer` (§ user request: long-press a slot's photo, drag
/// it onto another slot, release to swap both). Kept in its own file since it's a distinct,
/// self-contained gesture+animation concern layered on top of the renderer's own plain layout/
/// paint job — none of this affects `AlbumPageRenderer` when `onSwapPhotos` is left `nil`.

/// One in-flight drag: which slot/photo it started from, and where the finger currently is —
/// converted to the canvas's own local coordinate space (the same space every slot's frame is
/// computed in), so a drop point can be hit-tested directly against those frames.
struct AlbumSlotDragState {
    let sourceSlotId: String
    let sourceAssignment: AlbumPhotoAssignment
    let startLocation: CGPoint
    var currentLocation: CGPoint
}

/// A completed swap's reveal transition for one slot — draws `frozenAssignment` (that slot's own
/// photo from *before* the swap) on top of the new content already arriving from below via the
/// normal `assignments` prop, punched away by a circle growing from `anchor` (§ "vòng tròn mở to
/// dần ... như sóng nước mở rộng" — a circle opening outward like an expanding water ripple).
struct AlbumSlotRippleEffect {
    let frozenAssignment: AlbumPhotoAssignment
    let anchor: CGPoint
    var radius: CGFloat = 0
    let maxRadius: CGFloat
}

/// `rect` minus a circle of `radius` centered at `center` — an even-odd fill produces the "hole
/// punched in a rectangle" shape without needing `Shape.subtracting` (iOS 17+), so it works the
/// same regardless of OS version. `animatableData` interpolates `radius`/`center` frame-by-frame
/// under `withAnimation`, which is what actually makes the circle visibly grow rather than jump
/// straight from hidden to fully revealed.
struct AlbumSlotRippleMask: Shape {
    var center: CGPoint
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(radius, AnimatablePair(center.x, center.y)) }
        set {
            radius = newValue.first
            center = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        return path
    }
}

/// The circular "picked up" preview that follows the finger while dragging — § "sinh ra 1 hình
/// tròn to hơn điểm ngón tay 1 chút với hình của ảnh được chạm."
struct AlbumSlotDragPreview<Provider: AlbumSlotPhotoProviding>: View {
    let assignment: AlbumPhotoAssignment
    let photoProvider: Provider
    let position: CGPoint

    private static var diameter: CGFloat { 84 }

    var body: some View {
        photoProvider.photoView(reference: assignment.photo, crop: assignment.crop, contentMode: .fill)
            .frame(width: Self.diameter, height: Self.diameter)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .position(position)
            .allowsHitTesting(false)
    }
}

/// One side of a completed swap — enough for `AlbumPageRenderer.beginSwapRipple` to start that
/// slot's reveal transition (`anchor`/`rect`) and report the actual data change (`assignment`).
struct AlbumSlotSwapEndpoint {
    let slotId: String
    let assignment: AlbumPhotoAssignment
    /// The touch point (pickup point for the source, drop point for the target), expressed
    /// relative to `rect`'s own origin — the coordinate space `AlbumSlotRippleMask` needs, since
    /// the mask is applied to that one slot's own local content, not the whole canvas.
    let anchor: CGPoint
    let rect: CGRect
}

/// A touch that's been down long enough to *maybe* become a drag-to-swap, but hasn't yet — tracked
/// separately from `AlbumSlotDragState` (which only exists once a touch has actually been
/// promoted) so a quick tap never spawns anything visible at all. `token` distinguishes this touch
/// from any later one a stale, already-fired timer might otherwise still apply to.
struct AlbumSlotPendingPress {
    let token: UUID
    let startLocation: CGPoint
    var latestLocation: CGPoint
}

extension View {
    /// Attaches the hold-then-drag swap gesture (§ user request) to a slot's rendered content —
    /// hold in place to "pick up" the photo (spawns `AlbumSlotDragState`, which `AlbumPageRenderer`
    /// renders as the floating circular preview and the dimmed source slot), drag anywhere,
    /// release over a *different* slot that also has a real photo assigned to swap the two.
    /// Released anywhere else (empty background, back onto the same slot, an empty placeholder
    /// slot, or — critically — before the hold threshold below is even reached) cancels with no
    /// visible effect at all. `isEnabled: false` (or no assignment to drag in the first place)
    /// attaches no gesture at all — same "opt-in, zero overhead otherwise" shape `onTapPhoto`
    /// already uses elsewhere in this renderer.
    ///
    /// § user report — a plain `DragGesture(minimumDistance: 0)`, not `LongPressGesture(...)
    /// .sequenced(before: DragGesture(...))`: a `.sequenced` gesture's own `onEnded` is documented
    /// to sometimes never fire at all if the touch lifts right as the long-press phase hands off
    /// to the drag phase, before any drag delta has actually been reported yet — which is exactly
    /// "long-press just long enough to spawn the circle, then release immediately" and left
    /// `dragState` stuck showing that circle forever. A single, non-composite `DragGesture` doesn't
    /// have that failure mode — its `onEnded` reliably fires exactly once per touch, so `dragState`
    /// is *always* cleared there regardless of what happened. The hold-to-promote behavior is done
    /// by hand instead: `holdDuration` after touch-down, a timer checks whether the touch is still
    /// down and hasn't wandered past `promotionMovementTolerance` (ruling out an in-progress swipe)
    /// before actually spawning `dragState` — until that fires, nothing is shown at all, so a quick
    /// tap never produces a stray circle to begin with.
    ///
    /// Uses `.global` coordinate space, converted back to this canvas's own local space via
    /// `canvasOrigin` (`GeometryReader`'s `proxy.frame(in: .global).origin`, computed once by the
    /// caller) — not a shared named coordinate space, which previously made drag tracking silently
    /// stop working on any `AlbumPageRenderer` instance `TabView(.page)` (re)constructed while
    /// paging, since every simultaneously-alive instance (current + adjacent Pages, every layout
    /// picker swatch) declared that same string name at once.
    @ViewBuilder
    func albumSlotSwapGesture(
        isEnabled: Bool,
        slot: AlbumLayoutSlot,
        assignment: AlbumPhotoAssignment?,
        slotRect: CGRect,
        slotFrames: [String: CGRect],
        assignmentsBySlotId: [String: AlbumPhotoAssignment],
        dragState: Binding<AlbumSlotDragState?>,
        pendingPress: Binding<AlbumSlotPendingPress?>,
        canvasOrigin: CGPoint,
        onDropped: @escaping (_ source: AlbumSlotSwapEndpoint, _ target: AlbumSlotSwapEndpoint) -> Void
    ) -> some View {
        if isEnabled, let assignment {
            let holdDuration = 0.18
            let promotionMovementTolerance: CGFloat = 12

            // § user report, round 2 — `.highPriorityGesture(_:including:)` with a dynamic mask
            // (`.none` before promotion, `.all` after — the technique `AlbumPhotoPreviewView`'s
            // own pan-while-zoomed gesture uses) turned out to be the wrong tool here: per
            // `GestureMask`'s actual documented meaning, `.none` doesn't mean "track but don't
            // claim priority" — it means "disable this gesture entirely, including its own
            // `onChanged`." With that mask applied *before* promotion, this `DragGesture` never
            // received any events at all during exactly the window it needs to be watching touch
            // duration/movement to decide whether to promote — so holding never worked, at all.
            //
            // `.simultaneousGesture` instead: this gesture always tracks (its `onChanged`/
            // `onEnded` always fire, so the hold-timer below always gets a chance to run), and it
            // never blocks `TabView(.page)`'s own pan recognizer from *also* tracking the same
            // touch. A quick swipe still pages normally, since nothing here ever promotes for one
            // (the timer either never fires before release, or the movement tolerance check below
            // fails) — the trade-off is that once a drag *is* promoted, TabView's own recognizer
            // is still nominally free to also react if the subsequent motion reads as a page-swipe
            // to it, which `.highPriorityGesture` would have prevented; in practice the drag target
            // is another slot on the same, currently-visible Page, not a full edge-to-edge swipe,
            // so this hasn't been an issue.
            simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { drag in
                        let location = CGPoint(x: drag.location.x - canvasOrigin.x, y: drag.location.y - canvasOrigin.y)

                        if dragState.wrappedValue != nil {
                            dragState.wrappedValue?.currentLocation = location
                            return
                        }

                        guard let pending = pendingPress.wrappedValue else {
                            // Fresh touch-down — start the short hold timer. Nothing is shown yet.
                            let token = UUID()
                            pendingPress.wrappedValue = AlbumSlotPendingPress(token: token, startLocation: location, latestLocation: location)
                            DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) {
                                guard let stillPending = pendingPress.wrappedValue, stillPending.token == token else { return }
                                let moved = hypot(
                                    stillPending.latestLocation.x - stillPending.startLocation.x,
                                    stillPending.latestLocation.y - stillPending.startLocation.y
                                )
                                guard moved <= promotionMovementTolerance else { return }
                                dragState.wrappedValue = AlbumSlotDragState(
                                    sourceSlotId: slot.id, sourceAssignment: assignment,
                                    startLocation: stillPending.latestLocation, currentLocation: stillPending.latestLocation
                                )
                            }
                            return
                        }
                        pendingPress.wrappedValue = AlbumSlotPendingPress(token: pending.token, startLocation: pending.startLocation, latestLocation: location)
                    }
                    .onEnded { drag in
                        pendingPress.wrappedValue = nil
                        let source = dragState.wrappedValue
                        dragState.wrappedValue = nil
                        // Never promoted (a quick tap, or a swipe that moved too far first) — no
                        // drag was ever actually shown, so there's nothing to cancel or drop.
                        guard let source else { return }

                        let dropLocation = CGPoint(x: drag.location.x - canvasOrigin.x, y: drag.location.y - canvasOrigin.y)
                        // Hit-test the drop point against every *other* slot's frame — dropping
                        // back onto the same slot, on empty background, or on a slot with no
                        // photo assigned all fall through here and cancel with no effect.
                        guard
                            let targetEntry = slotFrames.first(where: { $0.key != slot.id && $0.value.contains(dropLocation) }),
                            let targetAssignment = assignmentsBySlotId[targetEntry.key]
                        else { return }

                        let targetRect = targetEntry.value
                        let sourceEndpoint = AlbumSlotSwapEndpoint(
                            slotId: slot.id, assignment: assignment,
                            anchor: CGPoint(x: source.startLocation.x - slotRect.minX, y: source.startLocation.y - slotRect.minY),
                            rect: slotRect
                        )
                        let targetEndpoint = AlbumSlotSwapEndpoint(
                            slotId: targetEntry.key, assignment: targetAssignment,
                            anchor: CGPoint(x: dropLocation.x - targetRect.minX, y: dropLocation.y - targetRect.minY),
                            rect: targetRect
                        )
                        onDropped(sourceEndpoint, targetEndpoint)
                    }
            )
        } else {
            self
        }
    }
}
