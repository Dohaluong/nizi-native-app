//
//  MemorySelectionEditView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import SwiftUI

/// "Chỉnh ảnh" from the Memory Viewer (docs/sprint/SPRINT-FIRST-MEMORY-EXPERIENCE.md § 15) — not
/// a new photo picker, just a toggle grid over the Event's existing curation result. Reuses
/// `EventCurationRepository.updateItemSelection` verbatim (same persistence `EventDetailView`'s
/// own selection UI uses), so manual choices continue to win over the algorithm everywhere.
struct MemorySelectionEditView: View {
    let candidate: MemoryCandidate
    /// `(updatedAssetIDs, changed)` — fired once, when the sheet is dismissed.
    let onDone: (_ selectedAssetIDs: [String], _ changed: Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var curationResult: EventCurationResult?
    @State private var isLoading = true
    @State private var assetProvider: PhotoAssetProvider = PhotoKitAssetProvider()

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 4)]

    var body: some View {
        ScrollView {
            if let curationResult {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(orderedItems(in: curationResult)) { item in
                        SelectionThumbnailCell(item: item, assetProvider: assetProvider) {
                            toggle(itemID: item.id)
                        }
                    }
                }
                .padding(4)
            } else if isLoading {
                ProgressView().padding(.top, 60)
            }
        }
        .navigationTitle("memory_selection_edit.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.action.done", action: finish)
            }
        }
        .task { await load() }
    }

    private func orderedItems(in result: EventCurationResult) -> [PhotoCurationItem] {
        result.groups
            .sorted { $0.sortOrder < $1.sortOrder }
            .flatMap { group in group.items.sorted { $0.sortOrder < $1.sortOrder } }
    }

    private func load() async {
        let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
        curationResult = try? await store.result(for: candidate.eventID)
        isLoading = false
    }

    private func toggle(itemID: UUID) {
        guard var result = curationResult else { return }
        for groupIndex in result.groups.indices {
            guard let itemIndex = result.groups[groupIndex].items.firstIndex(where: { $0.id == itemID }) else { continue }
            let newIsSelected = !result.groups[groupIndex].items[itemIndex].isSelected
            let source: SelectionSource = newIsSelected ? .userAdded : .userRemoved
            result.groups[groupIndex].items[itemIndex].isSelected = newIsSelected
            result.groups[groupIndex].items[itemIndex].selectionSource = source
            curationResult = result

            Task {
                let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
                try? await store.updateItemSelection(itemID: itemID, isSelected: newIsSelected, source: source)
            }
            break
        }
    }

    private func finish() {
        let updated = curationResult?.orderedSelectedAssetIdentifiers ?? candidate.selectedAssetIDs
        let changed = Set(updated) != Set(candidate.selectedAssetIDs)
        if changed {
            Task {
                let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
                try? await store.updateSelection(id: candidate.id, selectedAssetIDs: updated)
            }
        }
        onDone(updated, changed)
        dismiss()
    }
}

private struct SelectionThumbnailCell: View {
    let item: PhotoCurationItem
    let assetProvider: PhotoAssetProvider
    let onToggle: () -> Void

    @State private var image: PlatformImage?
    private static let targetSize = CGSize(width: 200, height: 200)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 92, height: 92)
            .clipped()

            Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(item.isSelected ? Color.accentColor : .white)
                .background(Circle().fill(item.isSelected ? Color.white : Color.black.opacity(0.35)))
                .padding(4)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .task(id: item.assetID) {
            image = assetProvider.cachedThumbnail(assetID: item.assetID, targetSize: Self.targetSize, contentMode: .fill)
            image = try? await assetProvider.requestThumbnail(
                assetID: item.assetID, targetSize: Self.targetSize,
                networkAccessAllowed: false, deliveryMode: .fast, contentMode: .fill
            )
        }
    }
}
