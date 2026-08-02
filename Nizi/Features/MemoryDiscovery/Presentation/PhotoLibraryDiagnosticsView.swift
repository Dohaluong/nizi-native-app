//
//  PhotoLibraryDiagnosticsView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI

/// Debug-only screen for inspecting Photos permission state.
/// Per docs/ui/memory-discovery.md § 10, this stays separate from user-facing UI
/// and confined to debug builds — see the entry point in ContentView.
struct PhotoLibraryDiagnosticsView: View {
    private let authorizationService: PhotoLibraryAuthorizationService
    @State private var status: PhotoAccessStatus = .notDetermined
    @State private var isRequesting = false
    #if DEBUG
    @AppStorage(DebugLocaleOverride.storageKey) private var localeOverrideRawValue: String = DebugLocaleOverride.system.rawValue
    #endif
    /// Home/Events/Trips/Photobook/Diagnostics act like tabs — see `HomeView.selectTab`'s doc
    /// comment. Threaded down so this screen's own bottom bar jumps directly to another tab.
    var onSelectTab: (NiziBottomTabBar.Tab) -> Void

    init(
        authorizationService: PhotoLibraryAuthorizationService = PhotoKitAuthorizationService(),
        onSelectTab: @escaping (NiziBottomTabBar.Tab) -> Void = { _ in }
    ) {
        self.authorizationService = authorizationService
        self.onSelectTab = onSelectTab
    }

    var body: some View {
        List {
            #if DEBUG
            Section("Localization") {
                Picker("Language", selection: $localeOverrideRawValue) {
                    ForEach(DebugLocaleOverride.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
            }
            #endif

            Section("Authorization") {
                LabeledContent("Status", value: status.debugDescription)

                Button {
                    Task { await requestAccess() }
                } label: {
                    if isRequesting {
                        ProgressView()
                    } else {
                        Text("Request Access")
                    }
                }
                .disabled(isRequesting)

                if status == .limited {
                    Button("Manage Selected Photos") {
                        authorizationService.presentLimitedLibraryPicker()
                    }
                }

                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }

            Section("Library") {
                NavigationLink("Scan Sample") {
                    PhotoLibraryScanSampleView()
                }
                .disabled(status != .full && status != .limited)

                NavigationLink("Local Memory Index") {
                    LibraryIndexScanView()
                }
                .disabled(status != .full && status != .limited)

                NavigationLink("Event Discovery Debug") {
                    EventDiscoveryDebugListView()
                }
                .disabled(status != .full && status != .limited)

                NavigationLink("Curation Diagnostics") {
                    CurationDiagnosticsListView()
                }
                .disabled(status != .full && status != .limited)

                NavigationLink("Photo Location Diagnostics") {
                    PhotoLocationDiagnosticsView()
                }
                .disabled(status != .full && status != .limited)

                NavigationLink("Real Album Photo Diagnostics") {
                    RealAlbumPhotoDiagnosticsView()
                }
                .disabled(status != .full && status != .limited)

                NavigationLink("Home Detection") {
                    HomeDetectionDiagnosticsView()
                }
                .disabled(status != .full && status != .limited)

                NavigationLink("Event Boundary") {
                    EventBoundaryDiagnosticsView()
                }
                .disabled(status != .full && status != .limited)

                NavigationLink("Fast Event Quality") {
                    FastEventQualityDiagnosticsView()
                }
                .disabled(status != .full && status != .limited)

                NavigationLink("Detected Trips") {
                    TripDiscoveryDiagnosticsView()
                }
                .disabled(status != .full && status != .limited)

                NavigationLink("Memory Potential") {
                    MemoryPotentialDiagnosticsView()
                }
                .disabled(status != .full && status != .limited)
            }

            // Placeholder-only — pure UI, no data source, not gated on `status`. Temporary design
            // comparisons; delete each entry once its design decision is made.
            Section("Design Concepts") {
                NavigationLink("Home — 1a The Memory Surface") {
                    HomeDesignPreview1A()
                }
            }

            // Placeholder-only — doesn't touch Photos, so not gated on `status` like the
            // section above.
            Section("Album Layout") {
                NavigationLink("Layout Gallery") {
                    AlbumLayoutGalleryPreview()
                }

                NavigationLink("Pages Preview") {
                    AlbumPagesPreview()
                }

                NavigationLink("Draft Planner") {
                    AlbumDraftPlanningPreview()
                }
            }

            // Placeholder-only — `PhotoEditorStandalonePreview` uses `MockPhotoRendering`, so
            // this doesn't touch Photos either, same reasoning as "Album Layout" above.
            Section("Photo Editor") {
                NavigationLink("Standalone Preview") {
                    PhotoEditorStandalonePreview()
                }
                NavigationLink("LUT Manager") {
                    PresetManagerView()
                }
                NavigationLink("Preset Tuning") {
                    PresetTuningPanelView()
                }
            }
        }
        .navigationTitle("Photo Library Diagnostics")
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) {
            NiziBottomTabBar(
                selected: .diagnostics,
                onHome: { onSelectTab(.home) },
                onEvents: { onSelectTab(.events) },
                onTrips: { onSelectTab(.trips) },
                onPhotobooks: { onSelectTab(.photobooks) },
                onDiagnostics: {}
            )
        }
        .task {
            status = await authorizationService.currentStatus()
        }
    }

    private func requestAccess() async {
        isRequesting = true
        status = await authorizationService.requestAccess()
        isRequesting = false
        NiziLogger.discovery.info("permission_requested result=\(String(describing: status), privacy: .public)")
    }
}

private extension PhotoAccessStatus {
    var debugDescription: String {
        switch self {
        case .notDetermined: "Not Determined"
        case .limited: "Limited"
        case .full: "Full"
        case .denied: "Denied"
        case .restricted: "Restricted"
        }
    }
}

#Preview {
    NavigationStack {
        PhotoLibraryDiagnosticsView()
    }
}
