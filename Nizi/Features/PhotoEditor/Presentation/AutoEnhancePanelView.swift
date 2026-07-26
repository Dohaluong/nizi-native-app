//
//  AutoEnhancePanelView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// The Auto Enhance tool tray (PHOTO-EDITOR.md § 9.2) — a prompt before running, then the
/// suggested values (visible, not hidden — § 9.3) plus Undo after.
struct AutoEnhancePanelView: View {
    let viewModel: PhotoEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.session.workingRecipe.autoEnhanceApplied {
                appliedState
            } else {
                promptState
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private var promptState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("photoEditor.autoEnhance.title")
                    .font(.headline)
            } icon: {
                Image(systemName: "sparkles")
            }
            Text("photoEditor.autoEnhance.description")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button("photoEditor.autoEnhance.apply") {
                    Task { await viewModel.applyAutoEnhance() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isAutoEnhanceRunning)

                if viewModel.isAutoEnhanceRunning {
                    ProgressView()
                }
            }
        }
    }

    private var appliedState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("photoEditor.autoEnhance.appliedTitle")
                .font(.headline)

            let changedParameters = AdjustParameter.allCases.filter { viewModel.adjustPercent(for: $0) != 0 }
            if changedParameters.isEmpty {
                Text("photoEditor.autoEnhance.noChanges")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(changedParameters) { parameter in
                    HStack {
                        Text(localizedString(dynamicKey: parameter.titleKey))
                            .font(.subheadline)
                        Spacer()
                        Text(Self.formattedValue(viewModel.adjustPercent(for: parameter)))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button("photoEditor.autoEnhance.undo") {
                viewModel.undoAutoEnhance()
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canUndoAutoEnhance)
        }
    }

    private static func formattedValue(_ percent: Double) -> String {
        let rounded = Int(percent.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }
}
