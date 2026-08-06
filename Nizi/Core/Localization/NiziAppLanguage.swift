import Foundation

/// A user-facing language preference shared by the primary Nizi menu and localization helpers.
/// `system` deliberately resolves on every read so an iOS language change is still respected.
enum NiziAppLanguage: String, CaseIterable, Identifiable {
    case system
    case vietnamese = "vi"
    case english = "en"

    static let storageKey = "nizi.appLanguage"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .vietnamese: Locale(identifier: "vi")
        case .english: Locale(identifier: "en")
        }
    }

    var title: String {
        switch self {
        case .system: "Theo hệ thống"
        case .vietnamese: "Tiếng Việt"
        case .english: "English"
        }
    }

    static var current: NiziAppLanguage {
        NiziAppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }
}
