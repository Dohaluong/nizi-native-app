//
//  PresetStripView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI

/// The Preset tool tray (PHOTO-EDITOR.md § 7.2) — a horizontally scrolling row of preset
/// thumbnails rendered from the photo actually being edited, plus an intensity slider for
/// whichever preset is selected. `viewModel` is a reference type, so this reads/writes it
/// directly; no `@Bindable`/`$`-binding plumbing needed for a plain `Slider(value: Binding(get:
/// set:))`.
struct PresetStripView: View {
    let viewModel: PhotoEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.presets) { preset in
                        PresetThumbnailButton(
                            preset: preset,
                            thumbnail: viewModel.presetThumbnails[preset.id],
                            isSelected: preset.id == viewModel.selectedPresetId
                        ) {
                            viewModel.selectPreset(preset)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            if viewModel.selectedPresetId != PresetDefinition.originalId {
                intensityRow
            }
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var intensityRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("photoEditor.preset.intensity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(viewModel.presetIntensityPercent.rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { viewModel.presetIntensityPercent },
                    set: { viewModel.presetIntensityPercent = $0 }
                ),
                in: 0...100
            )
        }
        .padding(.horizontal, 16)
    }
}

private struct PresetThumbnailButton: View {
    let preset: PresetDefinition
    let thumbnail: CGImage?
    let isSelected: Bool
    let action: () -> Void

    private var displayName: String {
        localizedString(dynamicKey: preset.shortNameKey, defaultValue: preset.shortName)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.2))
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1, orientation: .up)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: 64, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )

                Text(displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 72)
            }
        }
        .buttonStyle(.plain)
    }
}
