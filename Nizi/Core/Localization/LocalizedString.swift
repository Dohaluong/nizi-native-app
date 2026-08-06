//
//  LocalizedString.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/25/26.
//

import Foundation

/// Every interpolated/composed localized string (counts, formatted dates, error messages —
/// anything that can't just be a `Text("key")` literal) should go through this instead of
/// calling `String(localized:defaultValue:)` directly.
///
/// In a release build this is exactly `String(localized:defaultValue:)` — same behavior as
/// calling it directly, `locale` defaults to `.current`. In a debug build it also honors the
/// Diagnostics screen's language override (`DebugLocaleOverride`), so these interpolated
/// strings switch language in lockstep with plain `Text("key")` literals, which already react
/// to the `.environment(\.locale, ...)` applied at the app root — without this, only the
/// literal-key strings would visibly change when testing the override.
func localizedString(_ key: StaticString, defaultValue: String.LocalizationValue) -> String {
    #if DEBUG
    let debugOverride = DebugLocaleOverride.current
    let locale = debugOverride == .system ? NiziAppLanguage.current.locale : debugOverride.locale
    return String(localized: key, defaultValue: defaultValue, locale: locale)
    #else
    String(localized: key, defaultValue: defaultValue, locale: NiziAppLanguage.current.locale)
    #endif
}

/// Same as above, for keys that only exist as a runtime `String` (e.g. `AlbumPageLayout.nameKey`,
/// looked up by data rather than a compile-time literal) — `Text(someString)` would render
/// `someString` verbatim instead of resolving it as a catalog key, so this is required wherever a
/// dynamic key needs to go through the catalog. See docs/ALBUM_LAYOUT_SYSTEM.md § Localization.
func localizedString(dynamicKey key: String, defaultValue: String? = nil) -> String {
    #if DEBUG
    let debugOverride = DebugLocaleOverride.current
    let locale = debugOverride == .system ? NiziAppLanguage.current.locale : debugOverride.locale
    #else
    let locale = NiziAppLanguage.current.locale
    #endif
    let resolved = String(localized: String.LocalizationValue(key), locale: locale)
    // `String(localized:)` falls back to the key itself when no catalog entry matches — if the
    // caller gave us a nicer default, prefer that over showing the raw dot-path key.
    if resolved == key, let defaultValue {
        return defaultValue
    }
    return resolved
}
