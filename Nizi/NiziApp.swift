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
    #if DEBUG
    @AppStorage(DebugLocaleOverride.storageKey) private var localeOverrideRawValue: String = DebugLocaleOverride.system.rawValue
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if DEBUG
                .environment(\.locale, (DebugLocaleOverride(rawValue: localeOverrideRawValue) ?? .system).locale)
                // Forces SwiftUI to tear down and rebuild the entire view tree on a language
                // change. Needed because `localizedString(_:defaultValue:)` resolves to a plain
                // `String` via `Foundation.String(localized:locale:)` (not a `Text`-resolved
                // `LocalizedStringKey`), so views built from it have no environment dependency
                // SwiftUI can see — without `.id()` here, `.environment(\.locale, ...)` alone
                // doesn't invalidate them, and they keep showing whatever they last computed.
                .id(localeOverrideRawValue)
                #endif
        }
        .modelContainer(for: [
            MDLocalAsset.self, MDScanCheckpoint.self, MDPhotoSession.self, MDEventCandidate.self,
            MDEventCurationResult.self, MDPhotoCurationGroup.self, MDPhotoCurationItem.self,
            MDMemoryCandidate.self,
            MDLocationCluster.self, MDHomeAnchor.self, MDFamiliarPlace.self, MDPhotoTrip.self,
            MDAlbumDraft.self, MDPhotoEditRecipe.self, MDCollectionEditStyle.self,
            MDPresetOverride.self, MDCustomPreset.self
        ])
    }
}
