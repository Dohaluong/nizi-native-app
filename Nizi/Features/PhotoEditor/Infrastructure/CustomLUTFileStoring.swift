//
//  CustomLUTFileStoring.swift
//  Nizi
//
//  Created by Do Ha Luong on 7/26/26.
//

import Foundation

/// Copies a user-picked `.cube` file into app-writable storage — the bundle itself is read-only
/// once installed, so an imported LUT can never live alongside the 13 bundled ones under
/// `Nizi/Features/PhotoEditor/Infrastructure/`. `CubeLUTLoader` checks this same directory before
/// falling back to the bundle, so `PresetDefinition.lutResource` stays just a plain filename
/// either way — nothing downstream needs to know which source a given preset's LUT came from.
protocol CustomLUTFileStoring: Sendable {
    /// Returns the stored filename (a generated `<uuid>.cube`, not the original picked name) to
    /// use as `PresetDefinition.lutResource`.
    func store(fileURL: URL) throws -> String
    func remove(filename: String) throws
}

enum CustomLUTFileStoringError: Error, Equatable {
    case copyFailed
}

final class DocumentsCustomLUTFileStore: CustomLUTFileStoring, @unchecked Sendable {
    static let subdirectoryName = "CustomLUTs"

    private var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.subdirectoryName, isDirectory: true)
    }

    func store(fileURL: URL) throws -> String {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = "\(UUID().uuidString).cube"
        let destination = directory.appendingPathComponent(filename)

        // A file picked via `.fileImporter` may be a security-scoped URL (e.g. from iCloud Drive
        // or another app's Files provider) — accessing it without this can silently fail.
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            try fileManager.copyItem(at: fileURL, to: destination)
        } catch {
            throw CustomLUTFileStoringError.copyFailed
        }
        return filename
    }

    func remove(filename: String) throws {
        let url = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
