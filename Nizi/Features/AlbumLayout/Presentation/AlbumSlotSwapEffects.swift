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

extension View {
    /// Attaches the long-press-then-drag swap gesture (§ user request) to a slot's rendered
    /// content — long-press to "pick up" the photo (spawns `AlbumSlotDragState`, which
    /// `AlbumPageRenderer` renders as the floating circular preview and the dimmed source slot),
    /// drag anywhere, release over a *different* slot that also has a real photo assigned to swap
    /// the two. Released anywhere else (empty background, back onto the same slot, an empty
    /// placeholder slot) cancels with no effect. `isEnabled: false` (or no assignment to drag in
    /// the first place) attaches no gesture at all — same "opt-in, zero overhead otherwise" shape
    /// `onTapPhoto` already uses elsewhere in this renderer.
    ///
    /// Uses `.global` coordinate space, converted back to this canvas's own local space via
    /// `canvasOrigin` (`GeometryReader`'s `proxy.frame(in: .global).origin`, computed once by the
    /// caller) — not a shared named coordinate space. A `TabView(.page)` keeps 2-3 Pages' worth of
    /// `AlbumPageRenderer` alive at once (current + adjacent, for swipe transitions), and this
    /// screen's layout picker instantiates several more (one per swatch); every one of those
    /// previously declared the *same* string-named coordinate space simultaneously, which is
    /// exactly the kind of setup that made drag tracking silently stop working after paging to a
    /// page whose renderer instance was freshly (re)constructed — `.global` has no name to
    /// register or resolve, so there's nothing for multiple instances to collide over.
    @ViewBuilder
    func albumSlotSwapGesture(
        isEnabled: Bool,
        slot: AlbumLayoutSlot,
        assignment: AlbumPhotoAssignment?,
        slotRect: CGRect,
        slotFrames: [String: CGRect],
        assignmentsBySlotId: [String: AlbumPhotoAssignment],
        dragState: Binding<AlbumSlotDragState?>,
        canvasOrigin: CGPoint,
        onDropped: @escaping (_ source: AlbumSlotSwapEndpoint, _ target: AlbumSlotSwapEndpoint) -> Void
    ) -> some View {
        if isEnabled, let assignment {
            // `.highPriorityGesture`, not `.gesture` — TabView(.page) is UIKit-backed
            // (`UIPageViewController`) with its own pan recognizer for swipe-between-Pages; once a
            // long-press has actually succeeded here, this gesture needs to keep winning the touch
            // stream rather than risk losing it back to the page-swipe recognizer.
            highPriorityGesture(
                LongPressGesture(minimumDuration: 0.35)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onChanged { value in
                        switch value {
                        case .first(true):
                            // The long press succeeded — spawn the drag state (and with it, the
                            // floating preview + dimmed source) right away, centered on the slot,
                            // even before any finger movement has been reported yet.
                            if dragState.wrappedValue == nil {
                                let center = CGPoint(x: slotRect.midX, y: slotRect.midY)
                                dragState.wrappedValue = AlbumSlotDragState(
                                    sourceSlotId: slot.id, sourceAssignment: assignment,
                                    startLocation: center, currentLocation: center
                                )
                            }
                        case let .second(true, drag):
                            if let drag {
                                dragState.wrappedValue?.currentLocation = CGPoint(
                                    x: drag.location.x - canvasOrigin.x, y: drag.location.y - canvasOrigin.y
                                )
                            }
                        default:
                            break
                        }
                    }
                    .onEnded { value in
                        let source = dragState.wrappedValue
                        dragState.wrappedValue = nil
                        guard case let .second(true, drag) = value, let drag, let source else { return }
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
