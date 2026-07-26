//
//  HelloNiziView.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI

/// First-launch screen, shown only if the app has never completed a scan.
/// See docs/sprint/SPRINT-005-UI.md § 3.
struct HelloNiziView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("onboarding.hello.title")
                .font(.largeTitle.bold())

            Text("onboarding.hello.description")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button("onboarding.hello.action.start", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
    }
}

#Preview {
    HelloNiziView(onContinue: {})
}
