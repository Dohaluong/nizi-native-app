//
//  PhotobookExportSession.swift
//  Nizi
//
//  Created by Do Ha Luong on 8/2/26.
//

import Foundation

/// Owns the export `Task` across `AlbumDetailView`'s own re-renders — the same "a place to hold a
/// long-lived Task that must outlive any single SwiftUI body evaluation" justification
/// `PhotoEditorViewModel`/`BackgroundScanCoordinator` already use elsewhere in this codebase.
///
/// Exactly one export `Task` is ever active. `generation` is bumped on every `start(draft:)` —
/// every closure the *old* Task still holds (its `onProgress` callback, its own completion/catch
/// block) checks its own captured generation against `self.generation` before touching `state`, so
/// a stale Task finishing late (including one still unwinding after `cancel()`) can never clobber
/// whatever a newer `start(draft:)` call already put in `state`.
@MainActor
@Observable
final class PhotobookExportSession {
    enum State: Equatable {
        case idle
        case exporting(PhotobookExportProgress)
        /// `cancel()` was called; the old `Task` is still unwinding (finishing its current photo
        /// load/page render, then cleaning up) — a *distinct* state from `.idle` specifically so
        /// `canStart` can refuse a new `start(draft:)`/Retry until that cleanup genuinely finishes.
        case cancelling
        case completed(URL)
        case failed(String)
    }

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?
    private var generation = 0
    /// The directory the *current* (or just-finished) export owns — `PhotobookExport/<uuid>/` in
    /// the temp directory. Never reused across exports; a fresh one is created on every
    /// `start(draft:)`, including a Retry after a failure.
    private var sessionDirectory: URL?
    private let exporter: PhotobookPDFExporter

    init(exporter: PhotobookPDFExporter = PhotobookPDFExporter()) {
        self.exporter = exporter
    }

    var canStart: Bool {
        switch state {
        case .idle, .completed, .failed: return true
        case .exporting, .cancelling: return false
        }
    }

    func start(draft: AlbumDraft) {
        guard canStart else { return }
        cleanupSessionDirectory()

        generation += 1
        let thisGeneration = generation

        let directory = Self.makeSessionDirectory()
        sessionDirectory = directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            state = .failed(PhotobookExportError.sessionSetupFailed.localizedDescription ?? "")
            return
        }

        state = .exporting(PhotobookExportProgress(phase: .renderingPage(page: 0, totalPages: 0)))
        task = Task { [weak self, exporter] in
            do {
                let pdfURL = try await exporter.export(draft: draft, workingDirectory: directory) { [weak self] progress in
                    guard let self, self.generation == thisGeneration else { return }
                    self.state = .exporting(progress)
                }
                guard let self else { return }
                // The synchronous PDF-assembly step (`assemblePDF`) has no cancellation
                // checkpoint of its own — a `cancel()` requested while it was already running
                // lets the file finish writing rather than leaving a half-written PDF. Honor the
                // cancel intent here instead of silently reporting success.
                if Task.isCancelled {
                    self.finishAfterCancellation(generation: thisGeneration, directory: directory)
                    return
                }
                guard self.generation == thisGeneration else { return }
                guard FileManager.default.fileExists(atPath: pdfURL.path) else {
                    self.cleanup(directory: directory)
                    self.state = .failed(PhotobookExportError.writeFailed.localizedDescription ?? "")
                    return
                }
                self.state = .completed(pdfURL)
            } catch {
                guard let self, self.generation == thisGeneration else { return }
                self.cleanup(directory: directory)
                switch error {
                case PhotobookExportError.cancelled:
                    self.state = .idle
                case let exportError as PhotobookExportError:
                    self.state = .failed(exportError.localizedDescription ?? "Export failed")
                default:
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// Only ever moves `.exporting` → `.cancelling` — the *real* transition to `.idle` happens
    /// once the Task's own completion/catch block above actually finishes cleanup, never here
    /// directly. `task.cancel()` propagates into `PhotobookPDFExporter`, which cancels whatever
    /// PhotoKit request is currently in flight (`PhotobookExportPhotoLoading`'s own
    /// `withTaskCancellationHandler`) rather than leaving it running unobserved.
    func cancel() {
        guard case .exporting = state else { return }
        state = .cancelling
        task?.cancel()
    }

    /// Cleans up a finished (`.completed`/`.failed`) session's directory and resets to `.idle` —
    /// called when the export sheet itself is dismissed. Does nothing while `.exporting`/
    /// `.cancelling` (the sheet disables interactive dismissal for both, see
    /// `PhotobookExportProgressView`).
    func dismiss() {
        switch state {
        case .completed, .failed:
            cleanupSessionDirectory()
            state = .idle
        case .idle, .exporting, .cancelling:
            break
        }
    }

    private func finishAfterCancellation(generation: Int, directory: URL) {
        guard self.generation == generation else { return }
        cleanup(directory: directory)
        state = .idle
    }

    private func cleanup(directory: URL) {
        try? FileManager.default.removeItem(at: directory)
        if sessionDirectory == directory {
            sessionDirectory = nil
        }
    }

    private func cleanupSessionDirectory() {
        guard let sessionDirectory else { return }
        try? FileManager.default.removeItem(at: sessionDirectory)
        self.sessionDirectory = nil
    }

    private static func makeSessionDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotobookExport", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
