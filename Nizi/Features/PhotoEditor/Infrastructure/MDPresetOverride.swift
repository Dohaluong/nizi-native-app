//
//  MDPresetOverride.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import SwiftData

/// A user customization of one *bundled* preset — active state and/or display name overridden
/// from the management screen, without ever rewriting the read-only `presets.json` bundle
/// resource. No row here at all means "use the bundled preset exactly as shipped."
@Model
final class MDPresetOverride {
    @Attribute(.unique) var presetId: String
    var isActive: Bool = true
    var nameOverride: String?
    var shortNameOverride: String?
    var updatedAt: Date

    init(presetId: String, isActive: Bool, nameOverride: String?, shortNameOverride: String?, updatedAt: Date) {
        self.presetId = presetId
        self.isActive = isActive
        self.nameOverride = nameOverride
        self.shortNameOverride = shortNameOverride
        self.updatedAt = updatedAt
    }
}
