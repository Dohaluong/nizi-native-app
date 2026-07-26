//
//  UserScanProgressView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI
import SwiftData

/// Runs the scoped library scan, then event discovery, then hands off to Home.
/// Never opens Event List directly — see docs/sprint/SPRINT-005-ADDENUM.md.
struct UserScanProgressView: View {
    let scope: LibraryScanScope
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var checkpoint: ScanCheckpoint?
    @State private var pauseFlag = ScanPauseFlag()
    @State private var isRunningDiscovery = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("scan.progress.title")
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            if let checkpoint, let total = checkpoint.totalAssetsEstimated, total > 0 {
                VStack(spacing: 8) {
                    Text("\(checkpoint.processedCount) / \(total)")
                        .font(.headline)
                    ProgressView(value: Double(checkpoint.processedCount), total: Double(total))
                }
            } else {
                ProgressView()
            }

            if isRunningDiscovery {
                Text("scan.progress.discovering")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if checkpoint?.status == .running {
                Button("scan.progress.action.pause") { pauseFlag.requestPause() }
            } else if checkpoint?.status == .paused {
                Button("scan.progress.action.resume", action: runScan)
                    .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding(32)
        .onAppear(perform: runScan)
    }

    private func runScan() {
        pauseFlag.reset()
        errorMessage = nil

        Task { @MainActor in
            do {
                let store = SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
                let scanUseCase = ScanPhotoLibraryUseCase(
                    assetProvider: PhotoKitAssetProvider(),
                    assetRepository: store,
                    checkpointRepository: store
                )

                try await scanUseCase.execute(pauseFlag: pauseFlag, dateRanges: scope.dateRanges()) { progress in
                    checkpoint = progress
                }

                guard let finalStatus = checkpoint?.status,
                      finalStatus == .completed || finalStatus == .partiallyCompleted
                else {
                    // Paused — wait for the user to tap "Tiếp tục".
                    return
                }

                isRunningDiscovery = true
                let discoverUseCase = DiscoverEventsUseCase(
                    assetRepository: store,
                    sessionRepository: store,
                    eventRepository: store
                )
                try await discoverUseCase.execute()
                isRunningDiscovery = false

                onComplete()
            } catch {
                errorMessage = localizedString("scan.progress.error.failed", defaultValue: "Survey failed: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    UserScanProgressView(scope: .fullLibrary, onComplete: {})
        .modelContainer(
            for: [MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self],
            inMemory: true
        )
}
