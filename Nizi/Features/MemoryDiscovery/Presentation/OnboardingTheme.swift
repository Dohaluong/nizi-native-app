//
//  OnboardingTheme.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import SwiftUI

/// Shared dark, cinematic look for the Welcome → Permission → Scan onboarding sequence, matching
/// design concept "2a" in docs/design-system/Nizi Home Concepts.dc.html § t2. Newsreader is
/// bundled as regular + italic variable fonts and exposed through `Font.onboardingSerif`.
enum OnboardingTheme {
    static let ink = Color(hex: 0x0E0D10)
    static let cream = Color(hex: 0xF6F1EA)
    static let accent = Color(hex: 0xE1875B)
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension Font {
    static func onboardingSerif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Newsreader16pt-Regular", size: size).weight(newsreaderDisplayWeight(weight))
    }

    static func onboardingSerifItalic(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Newsreader16pt-Italic", size: size).weight(newsreaderDisplayWeight(weight))
    }

    /// Newsreader's native Medium/SemiBold cuts are visually denser than the system serif they
    /// replace. Shift requested display weights down one step while retaining a clear hierarchy.
    private static func newsreaderDisplayWeight(_ weight: Font.Weight) -> Font.Weight {
        if weight == .black || weight == .heavy { return .bold }
        if weight == .bold { return .semibold }
        if weight == .semibold { return .medium }
        if weight == .medium { return .regular }
        return weight
    }
}

/// The recurring 52pt accent pill CTA used on every onboarding frame.
struct OnboardingPillButton: View {
    let titleKey: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(titleKey)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OnboardingTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .background(OnboardingTheme.accent, in: Capsule())
    }
}

/// A dim secondary text link (e.g. "Maybe later").
struct OnboardingTextLink: View {
    let titleKey: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(titleKey)
                .font(.system(size: 13))
                .foregroundStyle(OnboardingTheme.cream.opacity(0.4))
        }
    }
}

/// Uppercase, letter-spaced eyebrow label (e.g. "Traveling back to").
struct OnboardingEyebrowLabel: View {
    let titleKey: LocalizedStringKey

    var body: some View {
        Text(titleKey)
            .font(.system(size: 12, weight: .medium))
            .tracking(2)
            .textCase(.uppercase)
            .foregroundStyle(OnboardingTheme.cream.opacity(0.5))
    }
}

/// Ink background with a subtle radial vignette — deliberately not a photo grid, since Welcome
/// and Permission both run before Photos access exists and there is no real photo to show yet.
struct OnboardingSolidBackground: View {
    var body: some View {
        ZStack {
            OnboardingTheme.ink
            RadialGradient(
                colors: [OnboardingTheme.ink.opacity(0.0), OnboardingTheme.ink.opacity(0.6)],
                center: .center,
                startRadius: 80,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}
