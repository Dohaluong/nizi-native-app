import Foundation
import SwiftData

/// Contains only resumable preparation metadata. The bearer token stays exclusively in Keychain.
@Model
final class MDGoogleDrivePreparation {
    @Attribute(.unique) var sessionID: String
    var createdAt: Date
    var totalAssets: Int
    var mode: String

    init(sessionID: String, totalAssets: Int, mode: GoogleDriveImportMode) {
        self.sessionID = sessionID
        createdAt = Date()
        self.totalAssets = totalAssets
        self.mode = mode.rawValue
    }
}

@ModelActor
actor GoogleDrivePreparationStore {
    func save(sessionID: String, totalAssets: Int, mode: GoogleDriveImportMode) throws {
        let descriptor = FetchDescriptor<MDGoogleDrivePreparation>(predicate: #Predicate { $0.sessionID == sessionID })
        if try modelContext.fetch(descriptor).first == nil { modelContext.insert(MDGoogleDrivePreparation(sessionID: sessionID, totalAssets: totalAssets, mode: mode)) }
        try modelContext.save()
    }

    func latest() throws -> GoogleDrivePreparationSnapshot? {
        try modelContext.fetch(FetchDescriptor<MDGoogleDrivePreparation>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])).first.map {
            GoogleDrivePreparationSnapshot(sessionID: $0.sessionID, totalAssets: $0.totalAssets, mode: GoogleDriveImportMode(rawValue: $0.mode) ?? .optimized)
        }
    }

    func delete(sessionID: String) throws {
        let descriptor = FetchDescriptor<MDGoogleDrivePreparation>(predicate: #Predicate { $0.sessionID == sessionID })
        if let record = try modelContext.fetch(descriptor).first { modelContext.delete(record); try modelContext.save() }
    }
}

struct GoogleDrivePreparationSnapshot: Sendable {
    let sessionID: String
    let totalAssets: Int
    let mode: GoogleDriveImportMode
}
