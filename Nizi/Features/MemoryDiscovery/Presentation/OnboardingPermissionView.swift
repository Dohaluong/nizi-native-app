//
//  OnboardingPermissionView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI

/// Shows a soft-ask screen before the real system permission dialog fires — matching design
/// concept "2a"'s Permission frame in docs/design-system/Nizi Home Concepts.dc.html § t2. Only
/// the soft-ask button's own tap calls `requestAccess()` (the real dialog trigger); on appear we
/// only ever read `currentStatus()`, so returning users who already granted access never see this
/// screen re-fire the system prompt. See docs/sprint/SPRINT-005-UI.md § 5.
struct OnboardingPermissionView: View {
    private let authorizationService: PhotoLibraryAuthorizationService
    let onGranted: () -> Void
    let onDeferred: () -> Void

    @State private var status: PhotoAccessStatus = .notDetermined
    @State private var isChecking = true

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
        ZStack {
            OnboardingSolidBackground()

            VStack(spacing: 24) {
                Spacer()
                content
                Spacer()
            }
            .padding(32)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            isChecking = true
            let current = await authorizationService.currentStatus()
            status = current
            isChecking = false
            if current == .full {
                onGranted()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isChecking {
            ProgressView().tint(OnboardingTheme.cream)
        } else {
            switch status {
            case .full:
                // Auto-advances via onGranted above; nothing to show here.
                ProgressView().tint(OnboardingTheme.cream)
            case .notDetermined:
                softAskContent
            case .limited:
                limitedContent
            case .denied, .restricted:
                deniedContent
            }
        }
    }

    private var softAskContent: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(OnboardingTheme.accent.opacity(0.15))
                    .frame(width: 60, height: 60)
                Image(systemName: "photo.badge.checkmark")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(OnboardingTheme.accent)
            }

            Text("onboarding.permission.softask.title")
                .font(.onboardingSerif(size: 28, weight: .medium))
                .foregroundStyle(OnboardingTheme.cream)
                .multilineTextAlignment(.center)

            Text("onboarding.permission.softask.message")
                .font(.system(size: 15))
                .foregroundStyle(OnboardingTheme.cream.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)

            OnboardingPillButton(titleKey: "onboarding.permission.softask.action.allow") {
                Task { await requestAndAdvance() }
            }
            .padding(.top, 8)

            OnboardingTextLink(titleKey: "common.action.later", action: onDeferred)
        }
    }

    private var limitedContent: some View {
        VStack(spacing: 16) {
            Text("onboarding.permission.limited.title")
                .font(.onboardingSerif(size: 24, weight: .medium))
                .foregroundStyle(OnboardingTheme.cream)
                .multilineTextAlignment(.center)
            Text("onboarding.permission.limited.message")
                .font(.system(size: 15))
                .foregroundStyle(OnboardingTheme.cream.opacity(0.7))
                .multilineTextAlignment(.center)

            OnboardingPillButton(titleKey: "common.action.continue", action: onGranted)
                .padding(.top, 8)

            OnboardingTextLink(titleKey: "onboarding.permission.limited.action.choose_more") {
                Task {
                    await authorizationService.presentLimitedLibraryPicker()
                    status = await authorizationService.currentStatus()
                }
            }
        }
    }

    private var deniedContent: some View {
        VStack(spacing: 16) {
            Text("onboarding.permission.denied.title")
                .font(.onboardingSerif(size: 24, weight: .medium))
                .foregroundStyle(OnboardingTheme.cream)
                .multilineTextAlignment(.center)

            Text("onboarding.permission.denied.message")
                .font(.system(size: 15))
                .foregroundStyle(OnboardingTheme.cream.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)

            OnboardingPillButton(titleKey: "common.action.open_settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .padding(.top, 8)

            OnboardingTextLink(titleKey: "common.action.later", action: onDeferred)
        }
    }

    private func requestAndAdvance() async {
        isChecking = true
        let resolved = await authorizationService.requestAccess()
        status = resolved
        isChecking = false
        if resolved == .full {
            onGranted()
        }
    }
}

#Preview {
    OnboardingPermissionView(onGranted: {}, onDeferred: {})
}
