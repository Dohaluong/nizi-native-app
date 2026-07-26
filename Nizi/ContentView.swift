//
//  ContentView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI
import SwiftData

/// Root flow coordinator: Hello Nizi → Scope Selection → Permission → Scan → Home.
/// Skips straight to Home on subsequent launches once a scan has completed.
/// See docs/sprint/SPRINT-005-UI.md § 2 and docs/sprint/SPRINT-005-ADDENUM.md.
private enum OnboardingStage: Equatable {
    case checking
    case helloNizi
    case scopeSelection
    case permission(scope: LibraryScanScope)
    case scanning(scope: LibraryScanScope)
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
                    HelloNiziView { stage = .scopeSelection }
                }

            case .scopeSelection:
                NavigationStack {
                    ScopeSelectionView { scope in stage = .permission(scope: scope) }
                }

            case .permission(let scope):
                NavigationStack {
                    OnboardingPermissionView(
                        onGranted: { stage = .scanning(scope: scope) },
                        onDeferred: { stage = .home }
                    )
                }

            case .scanning(let scope):
                NavigationStack {
                    UserScanProgressView(scope: scope) { stage = .home }
                }

            case .home:
                HomeView()
            }
        }
        .task { await determineInitialStage() }
    }

    private func determineInitialStage() async {
        do {
            let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
            if let checkpoint = try await store.checkpoint(for: .initial),
               checkpoint.status == .completed || checkpoint.status == .partiallyCompleted {
                stage = .home
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
            for: [MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self],
            inMemory: true
        )
}
