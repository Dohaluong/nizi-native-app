//
//  DebugLocaleOverride.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

#if DEBUG
import Foundation

/// Debug-only "force this language" switch, surfaced as a Picker in
/// `PhotoLibraryDiagnosticsView` so en/vi translations can be visually compared without
/// changing the simulator/device's system language. Never compiled into a release build —
/// same `#if DEBUG` convention as the rest of the Diagnostics screen tree.
enum DebugLocaleOverride: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case vietnamese = "vi"

    var id: String { rawValue }

    /// `.autoupdatingCurrent` for `.system` — i.e. "don't override anything," not a frozen
    /// snapshot of whatever the system locale happened to be at launch.
    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .vietnamese: Locale(identifier: "vi")
        }
    }

    var displayName: String {
        switch self {
        case .system: "System"
        case .english: "English"
        case .vietnamese: "Tiếng Việt"
        }
    }

    static let storageKey = "debug.localeOverride"

    /// Non-reactive read for use inside `localizedString(_:defaultValue:)`, called during
    /// plain `body` re-evaluation — reactivity for the *trigger* to re-evaluate `body` comes
    /// from the `@AppStorage` binding at the app root (`NiziApp`), not from this accessor.
    static var current: DebugLocaleOverride {
        DebugLocaleOverride(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }
}
#endif
