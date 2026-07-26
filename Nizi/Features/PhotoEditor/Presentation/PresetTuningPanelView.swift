//
//  PresetTuningPanelView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// DEBUG-only "Preset Tuning Panel" — a Lightroom/VSCO-style live color-grading tool for
/// `PresetDefinition`, reachable from `Home → Diagnostics → Photo Editor → Preset Tuning`. Every
/// slider re-renders the current sample photo in real time (debounced, no "Apply" button); the
/// result can be copied out as JSON, copied out as a `PresetDefinition(...)` Swift literal, or
/// persisted directly as a new usable preset via "Save as New Preset". Never compiled into a
/// Release build — see `PhotoLibraryDiagnosticsView`'s `#if DEBUG` gating at the call site.
struct PresetTuningPanelView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: PresetTuningViewModel?
    @State private var isImportingLUT = false
    @State private var isPickingPhoto = false

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Preset Tuning")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                let vm = PresetTuningViewModel(modelContainer: modelContext.container)
                viewModel = vm
                await vm.loadInitial()
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: PresetTuningViewModel) -> some View {
        // Preview stays pinned above the scroll area — the whole point of a live-tuning tool is
        // seeing the effect of a slider as you drag it, which a preview that scrolls out of view
        // the moment you reach the Style section defeats.
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                previewArea(viewModel)
            }
            .padding(.horizontal)
            .padding(.top)
            .background(.bar)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    presetPicker(viewModel)
                    lutRow(viewModel)
                    intensityRow(viewModel)

                    ForEach(PresetTuningParameter.bySection, id: \.0) { section, parameters in
                        sliderSection(section.rawValue, parameters, viewModel)
                    }

                    histogramView(viewModel)
                    jsonPanel(viewModel)
                    exportPanel(viewModel)
                    importPanel(viewModel)

                    HStack {
                        Button("Reset Current Preset", role: .destructive) { viewModel.resetCurrentPreset() }
                        Spacer()
                        Button("Choose Photo…") { isPickingPhoto = true }
                        Button("Next Sample") { viewModel.nextSample() }
                    }

                    if let statusMessage = viewModel.statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
        .fileImporter(isPresented: $isImportingLUT, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                Task { await viewModel.importLUT(fileURL: url) }
            }
        }
        .sheet(isPresented: $isPickingPhoto) {
            PhotoPickerView(
                onPick: { assetId in
                    isPickingPhoto = false
                    viewModel.useSample(assetId: assetId)
                },
                onCancel: { isPickingPhoto = false }
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Preset picker

    private func presetPicker(_ viewModel: PresetTuningViewModel) -> some View {
        Menu {
            ForEach(viewModel.presetOptions) { preset in
                Button(preset.name) { viewModel.selectPreset(preset) }
            }
        } label: {
            HStack {
                Text("Preset")
                Spacer()
                Text(viewModel.presetOptions.first { $0.id == viewModel.selectedPresetId }?.name ?? viewModel.selectedPresetId)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview

    @ViewBuilder
    private func previewArea(_ viewModel: PresetTuningViewModel) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.85))
            switch viewModel.loadState {
            case .loading:
                ProgressView().tint(.white)
            case .loaded(let image):
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .frame(height: 320)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in viewModel.setShowingOriginal(true) }
                .onEnded { _ in viewModel.setShowingOriginal(false) }
        )
        .overlay(alignment: .topTrailing) {
            if viewModel.isShowingOriginal {
                Text("Original")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(8)
            }
        }
        Text("Press & hold preview to compare with Original")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    // MARK: - LUT

    private func lutRow(_ viewModel: PresetTuningViewModel) -> some View {
        Menu {
            Button("None") { viewModel.selectLUT(resourceName: nil, dimension: nil) }
            ForEach(viewModel.knownLUTResources, id: \.self) { resource in
                Button(resource) {
                    let dimension = viewModel.presetOptions.first { $0.lutResource == resource }?.lutDimension
                    viewModel.selectLUT(resourceName: resource, dimension: dimension ?? 32)
                }
            }
            Button("Import New LUT…") { isImportingLUT = true }
        } label: {
            HStack {
                Text("LUT")
                Spacer()
                Text(viewModel.working.lutResource ?? "—")
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sliders

    private func intensityRow(_ viewModel: PresetTuningViewModel) -> some View {
        sliderRow(
            title: "Preset Intensity",
            valueLabel: "\(Int(viewModel.presetIntensityPercent.rounded()))%",
            value: Binding(
                get: { viewModel.presetIntensityPercent },
                set: { viewModel.setPresetIntensityPercent($0) }
            ),
            range: 0...100
        )
    }

    private func sliderSection(_ title: String, _ parameters: [PresetTuningParameter], _ viewModel: PresetTuningViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            ForEach(parameters) { parameter in
                sliderRow(
                    title: parameter.title,
                    valueLabel: String(format: "%.0f", viewModel.displayValue(for: parameter)),
                    value: Binding(
                        get: { viewModel.displayValue(for: parameter) },
                        set: { viewModel.setDisplayValue($0, for: parameter) }
                    ),
                    range: parameter.displayRange
                )
                .opacity(parameter.isClarityTODO ? 0.5 : 1)
            }
        }
    }

    private func sliderRow(title: String, valueLabel: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(valueLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    // MARK: - Histogram

    @ViewBuilder
    private func histogramView(_ viewModel: PresetTuningViewModel) -> some View {
        if let histogram = viewModel.histogram {
            VStack(alignment: .leading, spacing: 6) {
                Text("Histogram").font(.headline)
                HStack(spacing: 16) {
                    histogramStat("Brightness", histogram.averageBrightness)
                    histogramStat("Shadows clip", histogram.shadowClippingRatio)
                    histogramStat("Highlights clip", histogram.highlightClippingRatio)
                    histogramStat("Saturation", histogram.averageSaturation)
                }
                .font(.caption2)
            }
        }
    }

    private func histogramStat(_ label: String, _ value: Float) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text(String(format: "%.0f%%", value * 100)).monospacedDigit()
        }
    }

    // MARK: - JSON panel

    private func jsonPanel(_ viewModel: PresetTuningViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Preset JSON").font(.headline)
                Spacer()
                Button("Copy JSON") {
                    UIPasteboard.general.string = viewModel.jsonText
                }
                .font(.caption)
            }
            Text(viewModel.jsonText)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Export

    private func exportPanel(_ viewModel: PresetTuningViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export").font(.headline)
            TextField("New preset name", text: Binding(
                get: { viewModel.newPresetName },
                set: { viewModel.newPresetName = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            HStack {
                Button("Copy Swift Code") {
                    UIPasteboard.general.string = viewModel.generatePresetDefinitionCode()
                }
                Spacer()
                Button("Save as New Preset") {
                    Task { await viewModel.saveAsNewPreset() }
                }
                .buttonStyle(.borderedProminent)
            }
            .font(.caption)
        }
    }

    // MARK: - Import

    private func importPanel(_ viewModel: PresetTuningViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import JSON").font(.headline)
            TextEditor(text: Binding(
                get: { viewModel.importText },
                set: { viewModel.importText = $0 }
            ))
            .font(.system(.caption2, design: .monospaced))
            .frame(height: 100)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
            Button("Apply Imported JSON") { viewModel.applyImportedJSON() }
                .font(.caption)
        }
    }
}
