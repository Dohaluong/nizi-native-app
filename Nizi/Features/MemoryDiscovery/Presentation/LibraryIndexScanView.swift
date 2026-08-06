//
//  LibraryIndexScanView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI
import SwiftData

/// Debug-only screen for the Local Memory Index: run/pause/resume the batch scan,
/// inspect year/month coverage, and clear the on-device index.
/// See docs/sprint/SPRINT-003-LOCAL-MEMORY-INDEX.md.
struct LibraryIndexScanView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var checkpoint: ScanCheckpoint?
    @State private var yearMonthStats: [YearMonthCount] = []
    @State private var errorMessage: String?
    @State private var isScanRunning = false
    @State private var pauseFlag = ScanPauseFlag()
    @State private var showClearConfirmation = false

    var body: some View {
        List {
            Section("Scan") {
                if let checkpoint {
                    LabeledContent("Status", value: checkpoint.status.rawValue)
                    LabeledContent("Processed", value: "\(checkpoint.processedCount) / \(checkpoint.totalAssetsEstimated ?? 0)")
                    if checkpoint.failedCount > 0 {
                        LabeledContent("Failed", value: "\(checkpoint.failedCount)")
                    }
                    if let total = checkpoint.totalAssetsEstimated, total > 0 {
                        ProgressView(value: Double(checkpoint.processedCount), total: Double(total))
                    }
                } else {
                    Text("Not scanned yet")
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                HStack {
                    Button(startButtonTitle) {
                        startScan()
                    }
                    .disabled(isScanRunning || checkpoint?.status == .completed)

                    if isScanRunning {
                        Button("Pause") {
                            pauseFlag.requestPause()
                        }
                    }
                }
            }

            Section("Local Index") {
                Button("Refresh Stats") {
                    Task { await loadStats() }
                }
                ForEach(yearMonthStats) { stat in
                    LabeledContent("\(stat.year)-\(String(format: "%02d", stat.month))", value: "\(stat.count)")
                }
            }

            Section {
                Button("Clear Local Index", role: .destructive) {
                    showClearConfirmation = true
                }
            }
        }
        .navigationTitle("Local Memory Index")
        .task {
            await loadCheckpoint()
            await loadStats()
        }
        .confirmationDialog(
            "Xóa dữ liệu khám phá trên thiết bị?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                Task { await clearIndex() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Xóa toàn bộ chỉ mục cục bộ trên thiết bị. Ảnh trong Apple Photos không bị ảnh hưởng.")
        }
    }

    private var startButtonTitle: String {
        switch checkpoint?.status {
        case .paused: "Resume Scan"
        case .running: "Scanning…"
        default: "Start Scan"
        }
    }

    private func makeStore() -> SwiftDataMemoryDiscoveryStore {
        SwiftDataMemoryDiscoveryStore(modelContainer: modelContext.container)
    }

    private func loadCheckpoint() async {
        do {
            checkpoint = try await makeStore().checkpoint(for: .initial)
        } catch {
            errorMessage = "Failed to load checkpoint: \(error.localizedDescription)"
        }
    }

    private func loadStats() async {
        do {
            yearMonthStats = try await makeStore().yearMonthStatistics()
        } catch {
            errorMessage = "Failed to load stats: \(error.localizedDescription)"
        }
    }

    private func startScan() {
        pauseFlag.reset()
        isScanRunning = true
        errorMessage = nil

        let store = makeStore()
        let useCase = ScanPhotoLibraryUseCase(
            assetProvider: PhotoKitAssetProvider(),
            assetRepository: store,
            checkpointRepository: store
        )
        let flag = pauseFlag

        Task { @MainActor in
            do {
                try await useCase.execute(pauseFlag: flag) { progress in
                    checkpoint = progress
                }
                await loadStats()
            } catch {
                errorMessage = "Scan failed: \(error.localizedDescription)"
            }
            isScanRunning = false
        }
    }

    private func clearIndex() async {
        do {
            try await makeStore().clearAll()
            checkpoint = nil
            yearMonthStats = []
        } catch {
            errorMessage = "Clear failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        LibraryIndexScanView()
    }
    .modelContainer(for: NiziPersistentModels.memoryDiscovery, inMemory: true)
}
