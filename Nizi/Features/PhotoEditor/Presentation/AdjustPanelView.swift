//
//  AdjustPanelView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// The Adjust tool tray (PHOTO-EDITOR.md § 8.2) — a 2-row grid of the six parameters (each
/// showing its current value), a slider for whichever one is selected, and the three reset levels
/// § 8.4 asks for (this parameter / all Adjust / the whole photo).
struct AdjustPanelView: View {
    let viewModel: PhotoEditorViewModel
    @State private var selectedParameter: AdjustParameter = .exposure

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AdjustParameter.allCases) { parameter in
                    AdjustParameterButton(
                        parameter: parameter,
                        valuePercent: viewModel.adjustPercent(for: parameter),
                        isSelected: parameter == selectedParameter
                    ) {
                        selectedParameter = parameter
                    }
                }
            }
            .padding(.horizontal, 16)

            sliderRow
            resetButtonsRow
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
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
                Button("photoEditor.adjust.resetParameter") {
                    viewModel.resetAdjustParameter(selectedParameter)
                }
                .font(.caption2)
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

    private var resetButtonsRow: some View {
        HStack {
            Button("photoEditor.adjust.resetAll") { viewModel.resetAllAdjustments() }
                .font(.caption)
            Spacer()
            Button("photoEditor.adjust.resetPhoto", role: .destructive) { viewModel.resetEntirePhoto() }
                .font(.caption)
        }
        .padding(.horizontal, 16)
    }

    private static func formattedValue(_ percent: Double) -> String {
        let rounded = Int(percent.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }
}

private struct AdjustParameterButton: View {
    let parameter: AdjustParameter
    let valuePercent: Double
    let isSelected: Bool
    let action: () -> Void

    private var roundedValue: Int { Int(valuePercent.rounded()) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(localizedString(dynamicKey: parameter.titleKey))
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.primary : .secondary)
                    .lineLimit(1)
                Text(roundedValue == 0 ? "—" : (roundedValue > 0 ? "+\(roundedValue)" : "\(roundedValue)"))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(roundedValue == 0 ? Color.secondary : Color.accentColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.secondary.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
