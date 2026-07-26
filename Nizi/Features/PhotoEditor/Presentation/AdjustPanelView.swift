//
//  AdjustPanelView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// The Adjust tool tray (PHOTO-EDITOR.md § 8.2) — a row of icon buttons (Auto Enhance first, the
/// six parameters, Reset last), each with a caption below matching the Preset tab's own thumbnail-
/// plus-caption cells exactly (`PhotoEditorToolTrayMetrics`), plus a slider for whichever parameter
/// is currently selected. No numeric value sits on the icons themselves — it's already visible
/// beside the slider below, so restating it a second time on every icon was pure duplication.
struct AdjustPanelView: View {
    let viewModel: PhotoEditorViewModel
    @State private var selectedParameter: AdjustParameter = .exposure

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            iconRow
            sliderRow
        }
        .padding(.vertical, 12)
    }

    private var iconRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PhotoEditorToolTrayMetrics.cellSpacing) {
                autoButton
                ForEach(AdjustParameter.allCases) { parameter in
                    AdjustIconButton(
                        systemImage: parameter.systemImage,
                        caption: localizedString(dynamicKey: parameter.titleKey),
                        isSelected: parameter == selectedParameter,
                        isActive: viewModel.adjustPercent(for: parameter) != 0
                    ) {
                        selectedParameter = parameter
                    }
                }
                resetButton
            }
            .padding(.horizontal, PhotoEditorToolTrayMetrics.horizontalPadding)
        }
    }

    /// A momentary action, not a selectable slider target like the six parameters — tapping it
    /// runs (or, if already applied, undoes) Auto Enhance immediately; whichever parameter is
    /// currently selected keeps showing its own (now Auto-updated) value on the slider below, per
    /// § 9.3's "kết quả hiển thị, không ẩn."
    private var autoButton: some View {
        let isApplied = viewModel.session.workingRecipe.autoEnhanceApplied
        let canUndo = viewModel.canUndoAutoEnhance
        return AdjustIconButton(
            systemImage: "sparkles",
            caption: localizedString(dynamicKey: "photoEditor.tool.auto"),
            isSelected: false,
            isActive: isApplied,
            isLoading: viewModel.isAutoEnhanceRunning
        ) {
            if canUndo {
                viewModel.undoAutoEnhance()
            } else {
                Task { await viewModel.applyAutoEnhance() }
            }
        }
        .disabled(viewModel.isAutoEnhanceRunning)
    }

    /// The only reset action left in this tray — resets all six Adjust values back to `0`
    /// (`resetAllAdjustments`), not the more drastic "whole photo back to Original" (which also
    /// clears the selected preset) that used to sit alongside it as a second button; picking
    /// "Original" in the Preset tab already covers that case.
    private var resetButton: some View {
        AdjustIconButton(
            systemImage: "arrow.counterclockwise",
            caption: localizedString(dynamicKey: "photoEditor.adjust.resetAll"),
            isSelected: false,
            isActive: false
        ) {
            viewModel.resetAllAdjustments()
        }
    }

    /// No title — the parameter is already identified by which icon is selected above; just the
    /// slider and its live percentage, side by side (never stacked with a label above it).
    private var sliderRow: some View {
        HStack(spacing: 10) {
            Slider(
                value: Binding(
                    get: { viewModel.adjustPercent(for: selectedParameter) },
                    set: { viewModel.setAdjustPercent(selectedParameter, $0) }
                ),
                in: -100...100
            )
            Text(Self.formattedValue(viewModel.adjustPercent(for: selectedParameter)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, PhotoEditorToolTrayMetrics.horizontalPadding)
    }

    private static func formattedValue(_ percent: Double) -> String {
        let rounded = Int(percent.rounded())
        return rounded > 0 ? "+\(rounded)%" : "\(rounded)%"
    }
}

private struct AdjustIconButton: View {
    let systemImage: String
    let caption: String
    let isSelected: Bool
    let isActive: Bool
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(isSelected ? 0.16 : 0.08))
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 24))
                            .foregroundStyle(isSelected || isActive ? Color.accentColor : .white.opacity(0.85))
                    }
                }
                .frame(width: PhotoEditorToolTrayMetrics.cellSize, height: PhotoEditorToolTrayMetrics.cellSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )

                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white : .white.opacity(0.6))
                    .lineLimit(1)
                    .frame(maxWidth: PhotoEditorToolTrayMetrics.captionMaxWidth)
            }
        }
        .buttonStyle(.plain)
    }
}
