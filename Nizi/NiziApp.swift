//
//  NiziApp.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/24/26.
//

import SwiftUI
import SwiftData

@main
struct NiziApp: App {
    @AppStorage(NiziAppLanguage.storageKey) private var appLanguageRawValue: String = NiziAppLanguage.system.rawValue
    #if DEBUG
    @AppStorage(DebugLocaleOverride.storageKey) private var localeOverrideRawValue: String = DebugLocaleOverride.system.rawValue
    #endif

    init() {
        NewsreaderFontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // DESIGN-pinterest.md specifies a warm, light canvas as the product chrome.
                // Individual photo/crop viewers may still select a deliberate viewing surface.
                .preferredColorScheme(.light)
                .tint(NiziPinterestTheme.primary)
                .environment(\.locale, effectiveLocale)
                #if DEBUG
                // Forces SwiftUI to tear down and rebuild the entire view tree on a language
                // change. Needed because `localizedString(_:defaultValue:)` resolves to a plain
                // `String` via `Foundation.String(localized:locale:)` (not a `Text`-resolved
                // `LocalizedStringKey`), so views built from it have no environment dependency
                // SwiftUI can see — without `.id()` here, `.environment(\.locale, ...)` alone
                // doesn't invalidate them, and they keep showing whatever they last computed.
                .id("\(appLanguageRawValue)-\(localeOverrideRawValue)")
                #else
                .id(appLanguageRawValue)
                #endif
        }
        .modelContainer(for: NiziPersistentModels.app)
    }

    private var effectiveLocale: Locale {
        #if DEBUG
        let debugOverride = DebugLocaleOverride(rawValue: localeOverrideRawValue) ?? .system
        if debugOverride != .system { return debugOverride.locale }
        #endif
        return (NiziAppLanguage(rawValue: appLanguageRawValue) ?? .system).locale
    }
}
