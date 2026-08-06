//
//  ContentView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI
import SwiftData

/// Root flow coordinator: Welcome → Permission → Discovering (scan/discover/score/curate) →
/// Home. No Scope Selection in this flow — always the full accessible library
/// (see `ScopeSelectionView`'s own doc comment: kept for a future Diagnostics/Advanced entry
/// point, not part of onboarding). Skips straight to Home on subsequent launches once a Memory
/// already exists. See docs/sprint/SPRINT-FIRST-MEMORY-EXPERIENCE.md § 4/§ 22.
private enum OnboardingStage: Equatable {
    case checking
    case helloNizi
    case permission(scope: LibraryScanScope)
    case discovering(scope: LibraryScanScope)
    case home
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var stage: OnboardingStage = .checking
    /// Owns the scan/discover pipeline independent of whichever stage is currently on screen, so
    /// "Dừng lại, xem ngay" can keep indexing after the user moves on to Home. Lives here, not in
    /// any individual stage's View, because `ContentView` itself is never recreated across stage
    /// transitions — see `BackgroundScanCoordinator`'s own doc comment.
    @State private var backgroundScanCoordinator = BackgroundScanCoordinator()

    var body: some View {
        Group {
            switch stage {
            case .checking:
                ProgressView()

            case .helloNizi:
                NavigationStack {
                    HelloNiziView { stage = .permission(scope: .fullLibrary) }
                }

            case .permission(let scope):
                NavigationStack {
                    OnboardingPermissionView(
                        onGranted: { stage = .discovering(scope: scope) },
                        onDeferred: { stage = .home }
                    )
                }

            case .discovering(let scope):
                NavigationStack {
                    UserScanProgressView(scope: scope) { _ in stage = .home }
                }

            case .home:
                HomeView()
            }
        }
        .environment(backgroundScanCoordinator)
        .task {
            backgroundScanCoordinator.configure(modelContainer: modelContext.container)
            await determineInitialStage()
        }
    }

    /// A returning user whose index is already complete but who has no Memory yet (e.g. they
    /// deferred permission earlier, or the app was killed right after discovery) goes straight
    /// into `.discovering` — cheap, since `ScanPhotoLibraryUseCase` no-ops instantly on an
    /// already-`.completed` checkpoint, so this effectively just runs discover→score→curate.
    private func determineInitialStage() async {
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            if let checkpoint = try await store.checkpoint(for: .initial) {
                if checkpoint.status == .completed || checkpoint.status == .partiallyCompleted {
                    if try await store.fetchLatest() != nil {
                        stage = .home
                    } else {
                        stage = .discovering(scope: .fullLibrary)
                    }
                    return
                }
                // A scan interrupted mid-batch (.running/.paused) that already produced a
                // MemoryCandidate via an earlier "Dừng lại, xem ngay" shouldn't repeat onboarding
                // — go straight to Home; `HomeView.task` asks the coordinator to resume the rest
                // from this same persisted checkpoint. A plain interrupted scan that never
                // skipped ahead (no candidate yet) falls through to `.helloNizi` below, same as
                // before this feature existed.
                if checkpoint.status == .running || checkpoint.status == .paused,
                   try await store.fetchLatest() != nil {
                    stage = .home
                    return
                }
            }
        } catch {
            NiziLogger.discovery.error("initial_stage_check_failed")
        }
        stage = .helloNizi
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [
                MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
                MDEventCurationResult.self, MDPhotoCurationGroup.self, MDPhotoCurationItem.self,
                MDMemoryCandidate.self,
                MDLocationCluster.self, MDHomeAnchor.self, MDFamiliarPlace.self, MDPhotoTrip.self
            ],
            inMemory: true
        )
}
