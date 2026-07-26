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
            if viewModel.collectionStyle != nil {
                inheritanceIndicator
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.presets) { preset in
                        PresetThumbnailButton(
                            preset: preset,
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

    /// § 12.3 — makes the current inherit-vs-override state visible rather than a silent
    /// implementation detail (only shown at all when this photo belongs to an Album/Event that
    /// actually has a style saved).
    private var inheritanceIndicator: some View {
        Text(viewModel.isInheritingCollectionStyle ? "photoEditor.preset.inheritingStyle" : "photoEditor.preset.customStyle")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
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

/// Deliberately a static placeholder, not a live per-photo render — generating one via
/// `PhotoRenderEngine` for every preset was slow/unreliable enough in practice (14 concurrent
/// LUT renders) that it stood in the way of the one thing that actually matters: picking a preset
/// correctly applies its LUT to the main preview. A real thumbnail can come back later as its own,
/// separately-verified piece of work; this is a stable-per-preset color swatch (never
/// `String.hashValue`, which isn't stable across launches — docs/specs/SPEC-MODIFY-DRAFT.md § 11),
/// so at least every preset in the strip is visually distinguishable in the meantime.
private struct PresetThumbnailButton: View {
    let preset: PresetDefinition
    let isSelected: Bool
    let action: () -> Void

    private var displayName: String {
        localizedString(dynamicKey: preset.shortNameKey, defaultValue: preset.shortName)
    }

    private var swatchColor: Color {
        guard !preset.isOriginal else { return Color.secondary.opacity(0.2) }
        let hue = Double(Self.stableHash(preset.id) % 360) / 360
        return Color(hue: hue, saturation: 0.35, brightness: 0.55)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(swatchColor)
                    Image(systemName: preset.isOriginal ? "circle.slash" : "camera.filters")
                        .font(.system(size: 18))
                        .foregroundStyle(preset.isOriginal ? Color.secondary : .white.opacity(0.85))
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

    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for scalar in string.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
