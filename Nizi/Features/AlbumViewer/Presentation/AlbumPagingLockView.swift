//
//  AlbumPagingLockView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/30/26.
//

import SwiftUI
import UIKit

/// Reaches into `TabView(.page)`'s own `UIPageViewController`-backed `UIScrollView` to lock/unlock
/// page-turning directly at the UIKit level (§ user request: lock page-swiping entirely while a
/// photo drag is actively picked up, unlock once the swap finishes).
///
/// A SwiftUI-level `.highPriorityGesture` blocker (tried first, in `AlbumSlotSwapEffects.swift`'s
/// own gesture chain, dynamically masked `.none`/`.all` on `dragState`) was confirmed NOT to work
/// for this: `UIPageViewController`'s internal pan recognizer starts tracking a touch from the
/// very first instant it lands, and no SwiftUI gesture-priority trick can retroactively steal an
/// already-in-progress touch away from it mid-drag. This reaches past SwiftUI entirely instead.
///
/// Renders as an invisible, zero-interaction marker — it must be embedded as a genuine descendant
/// of one of the `TabView`'s own per-page items (see `AlbumPageViewer.pageView`), not floated
/// elsewhere in the view tree, so walking `superview` actually resolves to that page's own
/// `UIPageViewController` hierarchy rather than dead-ending somewhere else.
struct AlbumPagingLockView: UIViewRepresentable {
    var isLocked: Bool

    final class MarkerView: UIView {
        var isLocked = false {
            didSet { applyLockState() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                // Leaving the hierarchy entirely (Page torn down while off-screen) — always
                // restore scrolling rather than trusting whatever `isLocked` last said, so a
                // marker that disappears mid-drag can never strand paging locked forever.
                enclosingScrollView()?.isScrollEnabled = true
            } else {
                applyLockState()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyLockState()
        }

        private func applyLockState() {
            enclosingScrollView()?.isScrollEnabled = !isLocked
        }

        private func enclosingScrollView() -> UIScrollView? {
            var view = superview
            while let candidate = view {
                if let scrollView = candidate as? UIScrollView {
                    return scrollView
                }
                view = candidate.superview
            }
            return nil
        }
    }

    func makeUIView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isLocked = isLocked
        return view
    }

    func updateUIView(_ uiView: MarkerView, context: Context) {
        uiView.isLocked = isLocked
    }
}
