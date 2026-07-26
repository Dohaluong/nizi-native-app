//
//  SwiftDataCollectionStyleRepository.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation
import SwiftData

/// Production `CollectionStyleRepository` — same `@ModelActor` shape as every other repository in
/// this module.
@ModelActor
actor SwiftDataCollectionStyleRepository: CollectionStyleRepository {
    func getStyle(type: CollectionType, id: String) async throws -> CollectionEditStyle? {
        let key = MDCollectionEditStyle.key(type: type, id: id)
        var descriptor = FetchDescriptor<MDCollectionEditStyle>(predicate: #Predicate { $0.collectionKey == key })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.decodedStyle()
    }

    func saveStyle(_ style: CollectionEditStyle) async throws {
        let key = MDCollectionEditStyle.key(type: style.collectionType, id: style.collectionId)
        var descriptor = FetchDescriptor<MDCollectionEditStyle>(predicate: #Predicate { $0.collectionKey == key })
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(style)
        } else {
            modelContext.insert(MDCollectionEditStyle(style: style))
        }
        try modelContext.save()
    }
}
