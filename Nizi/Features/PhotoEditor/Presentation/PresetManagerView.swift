//
//  PresetManagerView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// LUT/preset management screen — list every preset (bundled or custom), toggle active, rename,
/// remove a custom one, and import a new `.cube` file. Reachable from `Home → Diagnostics → Photo
/// Editor → LUT Manager` (DEBUG builds only), the same convention every other internal tool in
/// this app uses. Backed by `CustomizablePresetRepository`'s `PresetManaging` conformance — this
/// view never touches SwiftData directly.
struct PresetManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var presets: [PresetDefinition] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var renameTarget: PresetDefinition?
    @State private var isImportingLUT = false
    @State private var pendingImport: ImportPending?
    /// Resolved once (`.task`, before first `reload()`) rather than recomputed on every `body`
    /// evaluation — `CustomizablePresetRepository`'s own `BundlePresetRepository` re-decodes and
    /// re-validates `presets.json` on its first call, so a fresh instance per access would repeat
    /// that work far more than a debug screen needs to.
    @State private var manager: CustomizablePresetRepository?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section {
                ForEach(presets) { preset in
                    PresetManagerRow(
                        preset: preset,
                        onToggleActive: { newValue in Task { await setActive(newValue, presetId: preset.id) } },
                        onRename: { renameTarget = preset },
                        onDelete: (manager?.isBundledPreset(id: preset.id) ?? true) ? nil : { Task { await remove(presetId: preset.id) } }
                    )
                }
            } header: {
                Text("photoEditor.lutManager.listHeader")
            } footer: {
                Text("photoEditor.lutManager.listFooter")
            }
        }
        .navigationTitle("photoEditor.lutManager.title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImportingLUT = true
                } label: {
                    Label("photoEditor.lutManager.import", systemImage: "plus")
                }
            }
        }
        .task {
            if manager == nil {
                manager = CustomizablePresetRepository(modelContainer: modelContext.container)
            }
            await reload()
        }
        .fileImporter(
            isPresented: $isImportingLUT,
            allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data, .data, .item],
            onCompletion: handleFileImportResult
        )
        .sheet(item: $pendingImport) { pending in
            ImportPresetSheet(
                onCancel: { pendingImport = nil },
                onSave: { name, shortName in
                    pendingImport = nil
                    Task { await addCustomPreset(fileURL: pending.url, name: name, shortName: shortName) }
                }
            )
        }
        .sheet(item: $renameTarget) { preset in
            RenamePresetSheet(
                preset: preset,
                onCancel: { renameTarget = nil },
                onSave: { name, shortName in
                    renameTarget = nil
                    Task { await rename(presetId: preset.id, name: name, shortName: shortName) }
                }
            )
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    private func reload() async {
        guard let manager else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            presets = try await manager.allPresets()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func setActive(_ isActive: Bool, presetId: String) async {
        guard let manager else { return }
        do {
            try await manager.setActive(isActive, presetId: presetId)
            await reload()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func rename(presetId: String, name: String, shortName: String) async {
        guard let manager else { return }
        do {
            try await manager.rename(presetId: presetId, name: name, shortName: shortName)
            await reload()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func remove(presetId: String) async {
        guard let manager else { return }
        do {
            try await manager.removeCustomPreset(id: presetId)
            await reload()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func addCustomPreset(fileURL: URL, name: String, shortName: String) async {
        guard let manager else { return }
        do {
            _ = try await manager.addCustomPreset(fileURL: fileURL, name: name, shortName: shortName, defaultIntensity: 0.85)
            await reload()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func handleFileImportResult(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            pendingImport = ImportPending(url: url)
        case let .failure(error):
            errorMessage = String(describing: error)
        }
    }
}

/// Wraps a picked file URL as `Identifiable` so `.sheet(item:)` can drive the "name this LUT"
/// prompt — the same "one atomic payload, not separate `isPresented`/data `@State` vars" idiom
/// `CurationPreviewPresentation` uses elsewhere in this app.
private struct ImportPending: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct PresetManagerRow: View {
    let preset: PresetDefinition
    let onToggleActive: (Bool) -> Void
    let onRename: () -> Void
    /// `nil` for a bundled preset — bundled presets can never be deleted, only deactivated.
    let onDelete: (() -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(localizedString(dynamicKey: preset.nameKey, defaultValue: preset.name))
                    .font(.body)
                Text(preset.lutResource ?? "—")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(
                "",
                isOn: Binding(get: { preset.isActive }, set: { onToggleActive($0) })
            )
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture { onRename() }
        .swipeActions(edge: .trailing, allowsFullSwipe: onDelete != nil) {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("photoEditor.lutManager.delete", systemImage: "trash")
                }
            }
            Button(action: onRename) {
                Label("photoEditor.lutManager.rename", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}

private struct RenamePresetSheet: View {
    let preset: PresetDefinition
    let onCancel: () -> Void
    let onSave: (String, String) -> Void

    @State private var name: String
    @State private var shortName: String

    init(preset: PresetDefinition, onCancel: @escaping () -> Void, onSave: @escaping (String, String) -> Void) {
        self.preset = preset
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: localizedString(dynamicKey: preset.nameKey, defaultValue: preset.name))
        _shortName = State(initialValue: localizedString(dynamicKey: preset.shortNameKey, defaultValue: preset.shortName))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("photoEditor.lutManager.nameField", text: $name)
                TextField("photoEditor.lutManager.shortNameField", text: $shortName)
            }
            .navigationTitle("photoEditor.lutManager.rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.action.cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("album.save") { onSave(name, shortName) }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ImportPresetSheet: View {
    let onCancel: () -> Void
    let onSave: (String, String) -> Void

    @State private var name = ""
    @State private var shortName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("photoEditor.lutManager.nameField", text: $name)
                    TextField("photoEditor.lutManager.shortNameField", text: $shortName)
                } footer: {
                    Text("photoEditor.lutManager.importFooter")
                }
            }
            .navigationTitle("photoEditor.lutManager.import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.action.cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("album.save") {
                        let resolvedShortName = shortName.trimmingCharacters(in: .whitespaces).isEmpty ? name : shortName
                        onSave(name, resolvedShortName)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
