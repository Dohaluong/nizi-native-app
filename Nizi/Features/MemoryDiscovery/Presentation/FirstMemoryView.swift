//
//  FirstMemoryView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/31/26.
//

import SwiftUI

/// The First Wow Moment (docs/sprint/SPRINT-FIRST-MEMORY-EXPERIENCE.md § 12) — shown right after
/// scanning/discovery finishes, before Home. `candidate == nil` means no Event cleared the
/// threshold; shows the graceful fallback from § 23 instead of a fabricated Memory.
struct FirstMemoryView: View {
    let candidate: MemoryCandidate?
    /// Pushing `MemoryViewerView` via `NavigationLink` here used to mean the system back
    /// gesture/button popped right back to this "we found a memory" announcement screen instead
    /// of reaching Home — a dead end (§ user report). Routing through a stage change instead (see
    /// `ContentView`'s `.memoryViewer` case) makes `MemoryViewerView` its own stack root, with no
    /// back destination at all — matching how every other onboarding stage already has no back.
    let onOpen: (MemoryCandidate) -> Void
    let onContinue: () -> Void

    @State private var assetProvider: PhotoAssetProvider = PhotoKitAssetProvider()
    @State private var coverImage: PlatformImage?

    private static let coverTargetSize = CGSize(width: 800, height: 800)

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if let candidate {
                Text("first_memory.title")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                coverView
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 24)

                VStack(spacing: 6) {
                    if let placeName = candidate.placeName {
                        Text(placeName)
                            .font(.headline)
                    }
                    Text(EventDateRangeFormatter.format(start: candidate.startDate, end: candidate.endDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(localizedString("first_memory.subtitle_count", defaultValue: "\(candidate.totalPhotoCount) moments"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    onOpen(candidate)
                } label: {
                    Text("first_memory.action.view")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 40)
                .padding(.top, 8)
            } else {
                Text("first_memory.empty.title")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("first_memory.empty.message")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: onContinue) {
                    Text("first_memory.action.continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }

            Spacer()
        }
        .padding(.vertical, 32)
        .task(id: candidate?.coverAssetID) {
            await loadCover()
        }
    }

    @ViewBuilder
    private var coverView: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
            }
        }
    }

    private func loadCover() async {
        guard let candidate else { return }
        coverImage = assetProvider.cachedThumbnail(
            assetID: candidate.coverAssetID, targetSize: Self.coverTargetSize, contentMode: .fill
        )
        do {
            coverImage = try await assetProvider.requestThumbnail(
                assetID: candidate.coverAssetID,
                targetSize: Self.coverTargetSize,
                networkAccessAllowed: true,
                deliveryMode: .highQuality,
                contentMode: .fill
            )
        } catch {
            NiziLogger.discovery.error("first_memory_cover_load_failed error=\(String(describing: error), privacy: .public)")
        }
    }
}

#Preview {
    NavigationStack {
        FirstMemoryView(candidate: nil, onOpen: { _ in }, onContinue: {})
    }
}
