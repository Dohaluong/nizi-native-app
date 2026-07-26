//
//  PhotoEditorToolTrayMetrics.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// Shared sizing/color for the Preset and Adjust tool trays — both `PresetStripView` and
/// `AdjustPanelView` build their own cell row from these same constants (never each picking their
/// own), and `PhotoEditorView.toolTray` applies `background`/`contentHeight` exactly once at the
/// container level. Switching tabs used to visibly jump — different backgrounds
/// (`.ultraThinMaterial` vs. a plain dark fill) and different natural content heights (a 40pt
/// icon-only row vs. a 64pt thumbnail-plus-caption row) — this is what makes that structurally
/// impossible instead of something each panel has to remember to match.
enum PhotoEditorToolTrayMetrics {
    static let cellSize: CGFloat = 64
    static let cellSpacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 16
    static let captionMaxWidth: CGFloat = 72
    static let background = Color.black.opacity(0.85)
    /// Fixed regardless of which tab's content is showing — a preset thumbnail row (with its
    /// caption) and an Adjust icon row (now the same `cellSize` plus its own caption) land at
    /// close to the same natural height already; this removes the last bit of drift.
    static let contentHeight: CGFloat = 170
}
