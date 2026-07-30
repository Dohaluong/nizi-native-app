//
//  PresetTuningViewModel.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import CoreGraphics
import CoreImage
import Foundation
import Photos
import SwiftData

/// Drives the DEBUG-only Preset Tuning Panel: pick a starting preset, live-tune its parameters with
/// sliders, see the result rendered on a real photo instantly, then either copy the result out as
/// JSON/Swift code or persist it as a new usable preset (`PresetManaging.saveCustomPreset`).
///
/// Renders through a real `PhotoRenderEngine`, same as production, but pointed at an
/// `AdHocPresetRepository` holding just the one in-flight working copy — the working preset is
/// never registered anywhere a real `PhotoEditRecipe`/`PresetRepository` lookup could find it until
/// "Save as New Preset" persists it for real, so this never risks a half-tuned preset leaking into
/// the real editor.
@MainActor
@Observable
final class PresetTuningViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded(CGImage)
        case failed(String)
    }

    private(set) var loadState: LoadState = .loading
    private(set) var isShowingOriginal = false
    private(set) var histogram: PhotoHistogramStatistics?

    private(set) var presetOptions: [PresetDefinition] = []
    private(set) var selectedPresetId: String = PresetDefinition.originalId
    /// The live-tuned copy every slider reads/writes — starts as a copy of whichever preset is
    /// selected, and diverges from it as the developer drags sliders. Never written back to
    /// `presetOptions`/`presetRepository` until "Save as New Preset".
    private(set) var working: PresetDefinition = .placeholder

    /// Every known `.cube` resource name across bundled + custom presets — the Preset Tuning
    /// Panel's LUT picker menu, so switching LUTs doesn't require re-importing a file that's
    /// already usable under some other preset.
    private(set) var knownLUTResources: [String] = []

    private(set) var sampleAssetIds: [String] = []
    private(set) var currentSampleIndex = 0

    var importText: String = ""
    var newPresetName: String = ""
    private(set) var statusMessage: String?

    var jsonText: String { PresetTuningJSON(preset: working).prettyPrinted() }

    private let renderEngine: PhotoRendering
    private let adHocRepository: AdHocPresetRepository
    private let presetManager: PresetManaging
    private let lutFileStore: CustomLUTFileStoring
    private let ciContext = CIContext(options: [.useSoftwareRenderer: true])

    private static let previewTargetSize = CGSize(width: 1000, height: 1000)
    private var renderGeneration = 0

    init(modelContainer: ModelContainer) {
        let manager = CustomizablePresetRepository(modelContainer: modelContainer)
        self.presetManager = manager
        self.lutFileStore = DocumentsCustomLUTFileStore()
        let adHoc = AdHocPresetRepository(initial: .placeholder)
        self.adHocRepository = adHoc
        self.renderEngine = PhotoRenderEngine(presetRepository: adHoc)
    }

    private var currentPhotoId: String? {
        sampleAssetIds.isEmpty ? nil : sampleAssetIds[currentSampleIndex]
    }

    // MARK: - Load

    func loadInitial() async {
        sampleAssetIds = Self.fetchRandomSampleAssetIds(limit: 12)

        // "Sticky" sample photo — whichever photo was on screen last time (via `nextSample()` or
        // `useSample(assetId:)`) reopens the panel already showing it, rather than a fresh random
        // pick every time, so a tuning session doesn't lose its reference photo just from
        // navigating away and back.
        if let pinnedId = UserDefaults.standard.string(forKey: Self.pinnedPhotoIdKey) {
            insertOrSelectSample(assetId: pinnedId)
        } else if let firstId = sampleAssetIds.first {
            persistCurrentPhotoId(firstId)
        }

        do {
            presetOptions = try await presetManager.allPresets()
        } catch {
            presetOptions = []
        }
        knownLUTResources = Array(Set(presetOptions.compactMap(\.lutResource))).sorted()

        if let first = presetOptions.first(where: { $0.id == selectedPresetId }) ?? presetOptions.first {
            selectPreset(first)
        } else {
            await refreshPreview()
        }
    }

    // MARK: - Preset selection / reset

    func selectPreset(_ preset: PresetDefinition) {
        selectedPresetId = preset.id
        working = preset
        Task { await refreshPreview() }
    }

    func resetCurrentPreset() {
        guard let original = presetOptions.first(where: { $0.id == selectedPresetId }) else { return }
        working = original
        Task { await refreshPreview() }
    }

    // MARK: - Sliders

    func displayValue(for parameter: PresetTuningParameter) -> Double {
        parameter.displayValue(in: working)
    }

    func setDisplayValue(_ value: Double, for parameter: PresetTuningParameter) {
        parameter.setDisplayValue(value, in: &working)
        Task { await refreshPreview(debounced: true) }
    }

    func setPresetIntensityPercent(_ percent: Double) {
        working.defaultIntensity = Float(min(max(percent, 0), 100) / 100)
        Task { await refreshPreview(debounced: true) }
    }

    var presetIntensityPercent: Double { Double(working.defaultIntensity) * 100 }

    // MARK: - HSL (selective color)

    func hslDisplayValue(_ component: HSLTuningComponent, for band: HSLColorBand) -> Double {
        component.displayValue(in: working.hsl[band])
    }

    func setHSLDisplayValue(_ value: Double, _ component: HSLTuningComponent, for band: HSLColorBand) {
        var adjustment = working.hsl[band]
        component.setDisplayValue(value, in: &adjustment)
        working.hsl[band] = adjustment
        Task { await refreshPreview(debounced: true) }
    }

    func isHSLBandEdited(_ band: HSLColorBand) -> Bool {
        !working.hsl[band].isIdentity
    }

    /// Resets just the one currently-selected band — matches the reference tool's own "Reset"
    /// button, which clears whichever color channel is active rather than every band at once.
    func resetHSLBand(_ band: HSLColorBand) {
        working.hsl[band] = HSLBandAdjustment()
        Task { await refreshPreview() }
    }

    // MARK: - LUT

    func selectLUT(resourceName: String?, dimension: Int?) {
        working.lutResource = resourceName
        working.lutDimension = resourceName == nil ? nil : dimension
        Task { await refreshPreview() }
    }

    /// Imports a brand-new `.cube` file the same way `PresetManagerView`'s importer does (copy into
    /// `DocumentsCustomLUTFileStore`, sniff the dimension), then immediately switches the working
    /// preset onto it — unlike `PresetManaging.addCustomPreset`, this never registers a whole new
    /// preset, just a new LUT resource this session can use.
    func importLUT(fileURL: URL) async {
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { fileURL.stopAccessingSecurityScopedResource() } }

        guard let text = try? String(contentsOf: fileURL, encoding: .utf8),
              let dimension = CubeFileParser.declaredDimension(in: text),
              (try? CubeFileParser.parse(text: text, expectedDimension: dimension)) != nil else {
            statusMessage = "Invalid .cube file"
            return
        }
        guard let filename = try? lutFileStore.store(fileURL: fileURL) else {
            statusMessage = "Could not import LUT"
            return
        }
        if !knownLUTResources.contains(filename) { knownLUTResources.append(filename) }
        selectLUT(resourceName: filename, dimension: dimension)
    }

    // MARK: - Sample cycling

    func nextSample() {
        guard !sampleAssetIds.isEmpty else { return }
        currentSampleIndex = (currentSampleIndex + 1) % sampleAssetIds.count
        persistCurrentPhotoId(sampleAssetIds[currentSampleIndex])
        Task { await refreshPreview() }
    }

    /// "Choose Photo" — tunes against one specific, developer-picked photo instead of only the
    /// shuffled "Next Sample" rotation.
    func useSample(assetId: String) {
        insertOrSelectSample(assetId: assetId)
        persistCurrentPhotoId(assetId)
        Task { await refreshPreview() }
    }

    /// Shared by `useSample(assetId:)` and the "sticky photo" restore in `loadInitial()` — inserted
    /// right before the current position (not appended at the end) so it becomes the very next
    /// `nextSample()` neighbor too, and reused in place if already present rather than duplicated.
    private func insertOrSelectSample(assetId: String) {
        if let existingIndex = sampleAssetIds.firstIndex(of: assetId) {
            currentSampleIndex = existingIndex
        } else {
            let insertionIndex = sampleAssetIds.isEmpty ? 0 : currentSampleIndex
            sampleAssetIds.insert(assetId, at: insertionIndex)
            currentSampleIndex = insertionIndex
        }
    }

    private static let pinnedPhotoIdKey = "presetTuning.pinnedPhotoAssetId"

    private func persistCurrentPhotoId(_ assetId: String) {
        UserDefaults.standard.set(assetId, forKey: Self.pinnedPhotoIdKey)
    }

    func setShowingOriginal(_ showingOriginal: Bool) {
        guard isShowingOriginal != showingOriginal else { return }
        isShowingOriginal = showingOriginal
        Task { await refreshPreview() }
    }

    // MARK: - JSON import/export

    func applyImportedJSON() {
        guard let data = importText.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(PresetTuningJSON.self, from: data) else {
            statusMessage = "Could not parse JSON"
            return
        }
        working = parsed.applying(to: working)
        statusMessage = "Imported"
        Task { await refreshPreview() }
    }

    /// A literal `PresetDefinition(...)` initializer call, formatted to paste straight into
    /// `presets.json`'s Swift-side neighbors — the exact "Claude sẽ tự sinh PresetDefinition(...)"
    /// shape from the spec, using `newPresetName` (or the working preset's own name as a fallback)
    /// to derive `id`/`name`/`shortName`.
    func generatePresetDefinitionCode() -> String {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? working.name : name
        let id = Self.slugify(displayName)
        func f(_ value: Float) -> String { String(format: "%.4g", value) }
        return """
        PresetDefinition(
            id: "\(id)", name: "\(displayName)", shortName: "\(displayName)",
            nameKey: "photoEditor.preset.custom.\(id).name", shortNameKey: "photoEditor.preset.custom.\(id).shortName",
            lutResource: \(working.lutResource.map { "\"\($0)\"" } ?? "nil"), lutDimension: \(working.lutDimension.map(String.init) ?? "nil"),
            defaultIntensity: \(f(working.defaultIntensity)),
            exposureOffset: \(f(working.exposureOffset)), contrastOffset: \(f(working.contrastOffset)), saturationOffset: \(f(working.saturationOffset)), warmthOffset: \(f(working.warmthOffset)),
            highlightsOffset: \(f(working.highlightsOffset)), shadowsOffset: \(f(working.shadowsOffset)),
            blacksOffset: \(f(working.blacksOffset)), whitesOffset: \(f(working.whitesOffset)), vibranceOffset: \(f(working.vibranceOffset)), tintOffset: \(f(working.tintOffset)),
            toneCurveAmount: \(f(working.toneCurveAmount)),
            grainAmount: \(f(working.grainAmount)), grainSize: \(f(working.grainSize)), bloomAmount: \(f(working.bloomAmount)), bloomRadius: \(f(working.bloomRadius)),
            vignetteAmount: \(f(working.vignetteAmount)), vignetteRadius: \(f(working.vignetteRadius)), sharpnessAmount: \(f(working.sharpnessAmount)), clarityOffset: \(f(working.clarityOffset)),
            hsl: \(Self.hslLiteral(working.hsl, f)),
            protectSkinTones: true, isMonochrome: false,
            thumbnailAssetName: nil, sortOrder: 0, isActive: true, isPrototype: false
        )
        """
    }

    // MARK: - Save as New Preset

    func saveAsNewPreset() async {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            statusMessage = "Enter a name first"
            return
        }
        var candidate = working
        candidate.name = name
        candidate.shortName = name

        var id = Self.slugify(name)
        let existingIds = Set(presetOptions.map(\.id))
        if existingIds.contains(id) {
            id = "\(id)-\(Int(Date().timeIntervalSince1970))"
        }
        candidate = PresetDefinition(
            id: id, name: candidate.name, shortName: candidate.shortName,
            nameKey: "photoEditor.preset.custom.\(id).name", shortNameKey: "photoEditor.preset.custom.\(id).shortName",
            lutResource: candidate.lutResource, lutDimension: candidate.lutDimension,
            defaultIntensity: candidate.defaultIntensity,
            exposureOffset: candidate.exposureOffset, contrastOffset: candidate.contrastOffset,
            saturationOffset: candidate.saturationOffset, warmthOffset: candidate.warmthOffset,
            highlightsOffset: candidate.highlightsOffset, shadowsOffset: candidate.shadowsOffset,
            blacksOffset: candidate.blacksOffset, whitesOffset: candidate.whitesOffset,
            vibranceOffset: candidate.vibranceOffset, tintOffset: candidate.tintOffset,
            toneCurveAmount: candidate.toneCurveAmount,
            grainAmount: candidate.grainAmount, grainSize: candidate.grainSize,
            bloomAmount: candidate.bloomAmount, bloomRadius: candidate.bloomRadius,
            vignetteAmount: candidate.vignetteAmount, vignetteRadius: candidate.vignetteRadius,
            sharpnessAmount: candidate.sharpnessAmount, clarityOffset: candidate.clarityOffset,
            hsl: candidate.hsl,
            protectSkinTones: true, isMonochrome: false,
            thumbnailAssetName: nil, sortOrder: 0, isActive: true, isPrototype: false
        )

        do {
            let saved = try await presetManager.saveCustomPreset(candidate)
            presetOptions.append(saved)
            newPresetName = ""
            statusMessage = "Saved as \"\(saved.name)\""
            selectPreset(saved)
        } catch {
            statusMessage = "Could not save: \(error)"
        }
    }

    // MARK: - Rendering

    private func refreshPreview(debounced: Bool = false) async {
        renderGeneration += 1
        let generation = renderGeneration

        if debounced {
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard generation == renderGeneration else { return }
        }

        guard let photoId = currentPhotoId else {
            loadState = .failed("No sample photos available (Photos library access needed)")
            return
        }

        adHocRepository.current = working
        var recipe = PhotoEditRecipe.original(photoId: photoId)
        if !isShowingOriginal {
            recipe.presetId = working.isOriginal ? nil : working.id
            recipe.presetIntensity = working.isOriginal ? 0 : working.defaultIntensity
        }

        let engine = renderEngine
        let targetSize = Self.previewTargetSize
        let image = await Task<CGImage?, Never> {
            try? await engine.renderPreview(photoId: photoId, recipe: recipe, targetSize: targetSize)
        }.value

        guard generation == renderGeneration else { return }

        if let image {
            loadState = .loaded(image)
            histogram = ImageAnalyzer.analyze(CIImage(cgImage: image), using: ciContext)
        } else {
            loadState = .failed("Render failed")
            histogram = nil
        }
    }

    // MARK: - Sample photo fetch

    private static func fetchRandomSampleAssetIds(limit: Int) -> [String] {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
            || PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited else { return [] }

        let options = PHFetchOptions()
        options.fetchLimit = 200
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)

        var ids: [String] = []
        result.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        return Array(ids.shuffled().prefix(limit))
    }

    /// `PresetHSLAdjustments()` (the plain no-op default) when every band is still identity — the
    /// common case, since most presets never touch HSL — otherwise a full 8-band literal.
    private static func hslLiteral(_ hsl: PresetHSLAdjustments, _ f: (Float) -> String) -> String {
        guard !hsl.isIdentity else { return "PresetHSLAdjustments()" }
        func band(_ name: String, _ adjustment: HSLBandAdjustment) -> String {
            "\(name): HSLBandAdjustment(hue: \(f(adjustment.hue)), saturation: \(f(adjustment.saturation)), lightness: \(f(adjustment.lightness)))"
        }
        let bands = [
            band("red", hsl.red), band("orange", hsl.orange), band("yellow", hsl.yellow), band("green", hsl.green),
            band("aqua", hsl.aqua), band("blue", hsl.blue), band("purple", hsl.purple), band("magenta", hsl.magenta),
        ].joined(separator: ", ")
        return "PresetHSLAdjustments(\(bands))"
    }

    private static func slugify(_ name: String) -> String {
        let lowered = name.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        let slug = lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(slug).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed.isEmpty ? "custom-\(UUID().uuidString.prefix(8))" : collapsed
    }
}

/// A `PresetRepository` of exactly one, mutable, in-memory preset — lets `PresetTuningViewModel`
/// reuse the real `PhotoRenderEngine`/`PresetRenderer` pipeline for a preset that isn't (yet)
/// persisted anywhere a normal `PresetRepository` lookup would find it.
private final class AdHocPresetRepository: PresetRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _current: PresetDefinition

    init(initial: PresetDefinition) { _current = initial }

    var current: PresetDefinition {
        get { lock.lock(); defer { lock.unlock() }; return _current }
        set { lock.lock(); _current = newValue; lock.unlock() }
    }

    func loadPresets() throws -> [PresetDefinition] { [current] }
    func preset(id: String) -> PresetDefinition? { current.id == id ? current : nil }
}

private extension PresetDefinition {
    static let placeholder = PresetDefinition(
        id: PresetDefinition.originalId, name: "Original", shortName: "Original",
        nameKey: "photoEditor.preset.original.name", shortNameKey: "photoEditor.preset.original.shortName",
        lutResource: nil, lutDimension: nil, defaultIntensity: 0,
        exposureOffset: 0, contrastOffset: 0, saturationOffset: 0, warmthOffset: 0,
        highlightsOffset: 0, shadowsOffset: 0,
        grainAmount: 0, grainSize: 0, bloomAmount: 0, bloomRadius: 0,
        vignetteAmount: 0, vignetteRadius: 0,
        protectSkinTones: true, isMonochrome: false,
        thumbnailAssetName: nil, sortOrder: 0, isActive: true, isPrototype: false
    )
}
