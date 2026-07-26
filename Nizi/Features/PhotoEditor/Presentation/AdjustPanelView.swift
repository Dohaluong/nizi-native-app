//
//  AdjustPanelView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// The Adjust tool tray (PHOTO-EDITOR.md § 8.2) — an icon-only row (Auto Enhance first, the six
/// parameters, Reset last) plus a slider for whichever parameter icon is currently selected. No
/// numeric label lives on the icons themselves — the value is already visible on the slider below,
/// so restating it a second time on every icon was pure duplication.
struct AdjustPanelView: View {
    let viewModel: PhotoEditorViewModel
    @State private var selectedParameter: AdjustParameter = .exposure

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            iconRow
            sliderRow
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var iconRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                autoButton
                ForEach(AdjustParameter.allCases) { parameter in
                    AdjustIconButton(
                        systemImage: parameter.systemImage,
                        accessibilityLabel: localizedString(dynamicKey: parameter.titleKey),
                        isSelected: parameter == selectedParameter,
                        isActive: viewModel.adjustPercent(for: parameter) != 0
                    ) {
                        selectedParameter = parameter
                    }
                }
                resetButton
            }
            .padding(.horizontal, 16)
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
            accessibilityLabel: localizedString(dynamicKey: canUndo ? "photoEditor.autoEnhance.undo" : "photoEditor.tool.auto"),
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
            accessibilityLabel: localizedString(dynamicKey: "photoEditor.adjust.resetAll"),
            isSelected: false,
            isActive: false
        ) {
            viewModel.resetAllAdjustments()
        }
    }

    private var sliderRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(localizedString(dynamicKey: selectedParameter.titleKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.formattedValue(viewModel.adjustPercent(for: selectedParameter)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { viewModel.adjustPercent(for: selectedParameter) },
                    set: { viewModel.setAdjustPercent(selectedParameter, $0) }
                ),
                in: -100...100
            )
        }
        .padding(.horizontal, 16)
    }

    private static func formattedValue(_ percent: Double) -> String {
        let rounded = Int(percent.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }
}

private struct AdjustIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let isSelected: Bool
    let isActive: Bool
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected || isActive ? Color.accentColor : Color.secondary)
                }
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
