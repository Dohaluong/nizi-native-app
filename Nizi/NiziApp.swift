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
    private let persistentContainer: ModelContainer
    @AppStorage(NiziAppLanguage.storageKey) private var appLanguageRawValue: String = NiziAppLanguage.system.rawValue
    #if DEBUG
    @AppStorage(DebugLocaleOverride.storageKey) private var localeOverrideRawValue: String = DebugLocaleOverride.system.rawValue
    #endif

    init() {
        NewsreaderFontRegistrar.registerBundledFonts()
        do {
            // Build the production container once, before any view can request a ModelContext.
            // Passing the concrete model types here keeps SwiftData's entity registration explicit
            // and prevents discovery from receiving a lightweight/index-only container.
            persistentContainer = try ModelContainer(
                for:
                    MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
                    MDEventCurationResult.self, MDPhotoCurationGroup.self, MDPhotoCurationItem.self,
                    MDMemoryCandidate.self, MDLocationCluster.self, MDHomeAnchor.self, MDFamiliarPlace.self,
                    MDPhotoTrip.self, MDAlbumDraft.self, MDPhotoEditRecipe.self, MDCollectionEditStyle.self,
                    MDPresetOverride.self, MDCustomPreset.self, MDNiziMoveImportSession.self,
                    MDNiziMoveImportAsset.self, MDGoogleDrivePreparation.self
            )
        } catch {
            fatalError("Không thể khởi tạo kho dữ liệu Nizi: \(error.localizedDescription)")
        }
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
        .modelContainer(persistentContainer)
    }

    private var effectiveLocale: Locale {
        #if DEBUG
        let debugOverride = DebugLocaleOverride(rawValue: localeOverrideRawValue) ?? .system
        if debugOverride != .system { return debugOverride.locale }
        #endif
        return (NiziAppLanguage(rawValue: appLanguageRawValue) ?? .system).locale
    }
}
