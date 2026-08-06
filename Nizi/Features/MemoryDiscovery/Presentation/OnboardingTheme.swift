//
//  OnboardingTheme.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/1/26.
//

import SwiftUI

/// Shared light onboarding chrome. The imagery-first product palette follows
/// `NiziUITests/DESIGN-pinterest.md`: quiet warm surfaces with one red primary action.
enum OnboardingTheme {
    static let ink = NiziPinterestTheme.canvas
    static let cream = NiziPinterestTheme.ink
    static let accent = NiziPinterestTheme.primary
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
        .background(OnboardingTheme.accent, in: RoundedRectangle(cornerRadius: NiziPinterestTheme.cornerRadius, style: .continuous))
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
                .foregroundStyle(OnboardingTheme.cream.opacity(0.6))
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

/// Quiet warm canvas — deliberately not a photo grid, since Welcome and Permission both run
/// before Photos access exists and there is no real photo to show yet.
struct OnboardingSolidBackground: View {
    var body: some View {
        ZStack {
            NiziPinterestTheme.surfaceSoft
            RadialGradient(
                colors: [NiziPinterestTheme.canvas.opacity(0.6), NiziPinterestTheme.surfaceCard.opacity(0.7)],
                center: .top,
                startRadius: 40,
                endRadius: 600
            )
        }
        .ignoresSafeArea()
    }
}
