//
//  HelloNiziView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI

/// First-launch screen, shown only if the app has never completed a scan. Matches design concept
/// "2a"'s Welcome frame in docs/design-system/Nizi Home Concepts.dc.html § t2 — the photo-count
/// stat and background photo grid are both dropped since neither exists pre-permission.
struct HelloNiziView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            OnboardingSolidBackground()

            VStack(spacing: 24) {
                Spacer()

                Text("Nizi")
                    .font(.onboardingSerif(size: 44, weight: .medium))
                    .foregroundStyle(OnboardingTheme.cream)

                Text("onboarding.hello.tagline")
                    .font(.onboardingSerifItalic(size: 21))
                    .foregroundStyle(OnboardingTheme.cream.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)

                Spacer()

                OnboardingPillButton(titleKey: "onboarding.hello.action.start", action: onContinue)
            }
            .padding(32)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    HelloNiziView(onContinue: {})
}
