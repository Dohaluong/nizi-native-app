//
//  OnboardingPermissionView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI

/// Requests Photos access right after scope confirmation (never on first app launch) and
/// shows the result — see docs/sprint/SPRINT-005-UI.md § 5.
struct OnboardingPermissionView: View {
    private let authorizationService: PhotoLibraryAuthorizationService
    let onGranted: () -> Void
    let onDeferred: () -> Void

    @State private var status: PhotoAccessStatus = .notDetermined
    @State private var isRequesting = true

    init(
        authorizationService: PhotoLibraryAuthorizationService = PhotoKitAuthorizationService(),
        onGranted: @escaping () -> Void,
        onDeferred: @escaping () -> Void
    ) {
        self.authorizationService = authorizationService
        self.onGranted = onGranted
        self.onDeferred = onDeferred
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            content
            Spacer()
        }
        .padding(32)
        .task { await refreshStatus(requestIfNotDetermined: true) }
    }

    @ViewBuilder
    private var content: some View {
        if isRequesting {
            ProgressView()
        } else {
            switch status {
            case .full, .notDetermined:
                // Full auto-advances via onGranted; notDetermined is transient while the
                // system prompt is up. Either way there's nothing for the user to tap here.
                ProgressView()
            case .limited:
                limitedContent
            case .denied, .restricted:
                deniedContent
            }
        }
    }

    private var limitedContent: some View {
        VStack(spacing: 16) {
            Text("onboarding.permission.limited.title")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("onboarding.permission.limited.message")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("common.action.continue", action: onGranted)
                .buttonStyle(.borderedProminent)
            Button("onboarding.permission.limited.action.choose_more") {
                Task {
                    await authorizationService.presentLimitedLibraryPicker()
                    await refreshStatus(requestIfNotDetermined: false)
                }
            }
        }
    }

    private var deniedContent: some View {
        VStack(spacing: 16) {
            Text("onboarding.permission.denied.title")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Button("common.action.open_settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            Button("common.action.later", action: onDeferred)
        }
    }

    private func refreshStatus(requestIfNotDetermined: Bool) async {
        isRequesting = true
        let current = await authorizationService.currentStatus()
        let resolved = (requestIfNotDetermined && current == .notDetermined)
            ? await authorizationService.requestAccess()
            : current
        status = resolved
        isRequesting = false
        if resolved == .full {
            onGranted()
        }
    }
}

#Preview {
    OnboardingPermissionView(onGranted: {}, onDeferred: {})
}
