//
//  MemoryViewerView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import SwiftUI

/// A lightweight, scrollable, emotional viewer for one `MemoryCandidate` — not the Photobook
/// engine (docs/sprint/SPRINT-FIRST-MEMORY-EXPERIENCE.md § 13: "nhanh, đơn giản, cảm xúc", no
/// template picker, no page editor, no drag-drop). Vertical scroll only, ~5 composition rules
/// cycling over the selected photos.
struct MemoryViewerView: View {
    let onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var candidate: MemoryCandidate
    @State private var isEditingSelection = false

    init(candidate: MemoryCandidate, onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
        _candidate = State(initialValue: candidate)
    }

    /// [1, 2, 1, 3] repeating — cover → single → pair → single → trio → single → pair … (§ 13.2).
    private static let compositionPattern = [1, 2, 1, 3]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                heroBlock
                ForEach(Array(compositionGroups.enumerated()), id: \.offset) { _, group in
                    compositionRow(assetIDs: group)
                }
            }
            .padding(.bottom, 32)
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            NiziLogger.discovery.info("first_memory_opened eventID=\(candidate.eventID, privacy: .public)")
        }
        .sheet(isPresented: $isEditingSelection) {
            NavigationStack {
                MemorySelectionEditView(candidate: candidate) { updatedAssetIDs, changed in
                    candidate.selectedAssetIDs = updatedAssetIDs
                    candidate.totalPhotoCount = updatedAssetIDs.count
                    if changed {
                        NiziLogger.discovery.info("first_memory_selection_edited eventID=\(candidate.eventID, privacy: .public)")
                    }
                }
            }
        }
    }

    // MARK: - Layout

    private var heroBlock: some View {
        VStack(spacing: 12) {
            MemoryPhotoCell(assetID: candidate.coverAssetID, contentMode: .fill)
                .frame(height: 380)
                .clipped()

            VStack(spacing: 4) {
                if let placeName = candidate.placeName {
                    Text(placeName)
                        .font(.title3.bold())
                }
                Text(EventDateRangeFormatter.format(start: candidate.startDate, end: candidate.endDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bodyAssetIDs: [String] {
        candidate.selectedAssetIDs.filter { $0 != candidate.coverAssetID }
    }

    private var compositionGroups: [[String]] {
        var groups: [[String]] = []
        var remaining = bodyAssetIDs
        var patternIndex = 0
        while !remaining.isEmpty {
            let count = min(Self.compositionPattern[patternIndex % Self.compositionPattern.count], remaining.count)
            groups.append(Array(remaining.prefix(count)))
            remaining.removeFirst(count)
            patternIndex += 1
        }
        return groups
    }

    @ViewBuilder
    private func compositionRow(assetIDs: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(assetIDs, id: \.self) { assetID in
                MemoryPhotoCell(assetID: assetID, contentMode: .fill)
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
            }
        }
        .frame(height: assetIDs.count == 1 ? 300 : 160)
        .padding(.horizontal, assetIDs.count == 1 ? 16 : 0)
        .clipShape(RoundedRectangle(cornerRadius: assetIDs.count == 1 ? 16 : 0))
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                isEditingSelection = true
            } label: {
                Label("memory_viewer.action.edit_selection", systemImage: "checklist")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                NiziLogger.discovery.info("first_experience_completed result=viewed")
                // Reached from onboarding: `onContinue` swaps `ContentView`'s whole stage to
                // `.home`. Reached from Home's own Memory section (a revisit): there's no stage
                // to swap, so `dismiss()` pops this pushed view back to Home instead.
                dismiss()
                onContinue()
            } label: {
                Text("memory_viewer.action.continue")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.bar)
    }
}

/// Single-asset image cell — plain PhotoKit thumbnail loading, same idiom as `EventCardView`/
/// `EventCoverView` (no crop/slot editing needed here, so `AlbumPhotoView` would be overkill).
private struct MemoryPhotoCell: View {
    let assetID: String
    let contentMode: ThumbnailContentMode

    @State private var assetProvider: PhotoAssetProvider = PhotoKitAssetProvider()
    @State private var image: PlatformImage?
    private static let targetSize = CGSize(width: 600, height: 600)

    private var swiftUIContentMode: SwiftUI.ContentMode {
        switch contentMode {
        case .fill: return .fill
        case .fit: return .fit
        }
    }

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: swiftUIContentMode)
            }
        }
        .task(id: assetID) {
            image = assetProvider.cachedThumbnail(assetID: assetID, targetSize: Self.targetSize, contentMode: contentMode)
            do {
                image = try await assetProvider.requestThumbnail(
                    assetID: assetID,
                    targetSize: Self.targetSize,
                    networkAccessAllowed: true,
                    deliveryMode: .highQuality,
                    contentMode: contentMode
                )
            } catch {
                NiziLogger.discovery.error("memory_photo_load_failed assetID=\(assetID, privacy: .private) error=\(String(describing: error), privacy: .public)")
            }
        }
    }
}
