//
//  ContentView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI
import SwiftData

/// Root flow coordinator: Welcome → Permission → Discovering (scan/discover/score/curate) →
/// First Memory → Home. No Scope Selection in this flow — always the full accessible library
/// (see `ScopeSelectionView`'s own doc comment: kept for a future Diagnostics/Advanced entry
/// point, not part of onboarding). Skips straight to Home on subsequent launches once a Memory
/// already exists. See docs/sprint/SPRINT-FIRST-MEMORY-EXPERIENCE.md § 4/§ 22.
private enum OnboardingStage: Equatable {
    case checking
    case helloNizi
    case permission(scope: LibraryScanScope)
    case discovering(scope: LibraryScanScope)
    case firstMemory(MemoryCandidate?)
    case memoryViewer(MemoryCandidate)
    case home
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var stage: OnboardingStage = .checking

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
                    UserScanProgressView(scope: scope) { candidate in stage = .firstMemory(candidate) }
                }

            case .firstMemory(let candidate):
                NavigationStack {
                    FirstMemoryView(
                        candidate: candidate,
                        onOpen: { opened in stage = .memoryViewer(opened) },
                        onContinue: { stage = .home }
                    )
                }

            // Its own stage (not a `NavigationLink` push from `.firstMemory`) so this screen is
            // always a stack root with no back destination — see `FirstMemoryView.onOpen`'s doc.
            case .memoryViewer(let candidate):
                NavigationStack {
                    MemoryViewerView(candidate: candidate) { stage = .home }
                }

            case .home:
                HomeView()
            }
        }
        .task { await determineInitialStage() }
    }

    /// A returning user whose index is already complete but who has no Memory yet (e.g. they
    /// deferred permission earlier, or the app was killed right after discovery) goes straight
    /// into `.discovering` — cheap, since `ScanPhotoLibraryUseCase` no-ops instantly on an
    /// already-`.completed` checkpoint, so this effectively just runs discover→score→curate.
    private func determineInitialStage() async {
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            if let checkpoint = try await store.checkpoint(for: .initial),
               checkpoint.status == .completed || checkpoint.status == .partiallyCompleted {
                if try await store.fetchLatest() != nil {
                    stage = .home
                } else {
                    stage = .discovering(scope: .fullLibrary)
                }
                return
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
